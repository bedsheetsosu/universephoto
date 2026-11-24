import Foundation
import Network
import TafelKit

/// One connection to a host: control channel (input, ping, config) + video channel.
/// Input is sent straight from the touch handler on the main thread; `FramedConnection.send`
/// is thread-safe, so no extra hop is added.
final class Session: @unchecked Sendable {
    struct Timing {
        var rttMs: Double
        var frameAgeMs: Double?
        var fps: Double
        var link: String
    }

    let queue = DispatchQueue(label: "tafel.client.net", qos: .userInteractive)
    let endpoint: NWEndpoint
    private let key: Data
    /// TLS identity that goes with the key (the iPad's own key, or the shared one of old pairings).
    private let identity: String
    private let hello: Hello
    private let renderer: VideoRenderer
    private let audioPlayer: AudioPlayer?

    var onHostInfo: ((HostInfo) -> Void)?
    var onAppInfo: ((AppInfo) -> Void)?
    var onSourceList: ((SourceList) -> Void)?
    var onPluginActions: (([PluginActionInfo]) -> Void)?
    var onToast: ((Toast) -> Void)?
    var onClipboard: ((ClipboardItem) -> Void)?
    var onScreenshot: ((Data) -> Void)?
    /// Palette JPEG (empty = removed), on the network queue.
    var onPalette: ((Data) -> Void)?
    var onSettingsPatch: (([String: Any]) -> Void)?
    /// The Mac gave this iPad its own key (moving an older pairing off the shared key).
    var onRekey: ((PairGrant) -> Void)?
    var onConnected: (() -> Void)?
    var onClosed: ((String?) -> Void)?
    var onTiming: ((Timing) -> Void)?

    private var control: FramedConnection?
    private var video: FramedConnection?
    private var pingTimer: DispatchSourceTimer?
    private var closed = false
    private var connected = false
    /// Control connection is ready and `hello` went out first (queue only).
    private var controlReady = false

    // Timing (queue only)
    private var rtt: Double = 0
    private var lastPong = Date()
    /// No pong for this long → the link is gone (e.g. USB drop-out). Much faster than a TCP timeout.
    static let deadAfter: TimeInterval = 2.5
    /// The cable attempt failed and Wi-Fi was used (main thread not guaranteed).
    var onCableFallback: (() -> Void)?
    private var clockOffset: Double?
    private var frameAges: [Double] = []
    private var framesThisSecond = 0
    private var lastConfig: ClientConfig?

    init(endpoint: NWEndpoint, key: Data, keyID: String?, deviceID: String, deviceName: String, renderer: VideoRenderer,
         audioPlayer: AudioPlayer? = nil) {
        self.endpoint = endpoint
        self.key = key
        self.identity = keyID.map(HostKey.deviceIdentity) ?? HostKey.pskIdentity
        self.hello = Hello(role: .control, deviceID: deviceID, deviceName: deviceName, keyID: keyID)
        self.renderer = renderer
        self.audioPlayer = audioPlayer
    }

    /// Interfaces to try first, in order (probably the USB cable), before falling back to Wi-Fi.
    var cableInterfaces: [NWInterface] = []
    /// Allow Äbbl peer-to-peer Wi-Fi (AWDL) for the Wi-Fi path.
    var peerToPeer = false
    /// Path of the control connection once ready, e.g. "USB-Kabel (en2)" (queue only).
    private(set) var linkDescription = ""
    private var pinnedInterface: NWInterface?
    private var fallbackLink: TafelNetwork.Link { peerToPeer ? .any : .noPeerToPeer }
    private var audio: FramedConnection?

    func start() {
        queue.async { [self] in
            connectControl(cable: cableInterfaces)
            queue.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self, !self.connected, !self.closed else { return }
                self.close(reason: L("Zeitüberschreitung beim Verbinden."))
            }
        }
    }

    /// Drops a connection without triggering its close handling.
    private func abandon(_ c: FramedConnection) {
        c.onClose = nil
        c.onState = nil
        c.onFrame = nil
        c.cancel()
    }

    /// Tries each cable candidate (2 s each), then Wi-Fi.
    private func connectControl(cable: [NWInterface]) {
        if cable.isEmpty, !cableInterfaces.isEmpty { onCableFallback?() }
        if let first = cable.first {
            connectControl(link: .pinned(first), next: { [weak self] in self?.connectControl(cable: Array(cable.dropFirst())) })
        } else {
            connectControl(link: fallbackLink, next: nil)
        }
    }

    private func connectControl(link: TafelNetwork.Link, next: (() -> Void)?) {
        let canFallBack = next != nil
        let c = FramedConnection(NWConnection(to: endpoint, using: TafelNetwork.parameters(psk: key, identity: identity, channel: .control, link: link)), queue: queue)
        control = c
        var ready = false
        let fallBack: () -> Void = { [weak self, weak c] in
            guard let self, let c, self.control === c, !ready, !self.closed else { return }
            self.abandon(c)
            next?()
        }
        if canFallBack {
            // No answer on this interface within 2 s → next candidate.
            queue.asyncAfter(deadline: .now() + 2, execute: fallBack)
        }
        c.onState = { [weak self, weak c] state in
            guard let self, let c else { return }
            switch state {
            case .ready:
                ready = true
                self.pinnedInterface = c.connection.currentPath?.availableInterfaces.first
                self.linkDescription = c.connection.linkDescription
                // Order matters: the host drops connections whose first frame is not `hello`.
                c.sendJSON(.hello, self.hello)
                self.controlReady = true
                if let cfg = self.lastConfig { c.sendJSON(.clientConfig, cfg) }
            case .waiting(let e):
                if canFallBack { fallBack() } else { self.close(reason: L("Mac nicht erreichbar: %@", e.localizedDescription)) }
            default:
                break
            }
        }
        c.onFrame = { [weak self] f in self?.handleControl(f) }
        c.onClose = { [weak self] e in
            if canFallBack && !ready { fallBack(); return }
            self?.close(reason: e.map { Self.describe($0) } ?? L("Verbindung vom Mac beendet."))
        }
        c.start()
    }

    /// Video and audio follow the control connection's interface, so all three use the cable
    /// (or all three Wi-Fi).
    private var dataLink: TafelNetwork.Link { pinnedInterface.map { .pinned($0) } ?? fallbackLink }

    private func startVideo() {
        guard video == nil else { return }
        let v = FramedConnection(NWConnection(to: endpoint, using: TafelNetwork.parameters(psk: key, identity: identity, channel: .video, link: dataLink)), queue: queue)
        video = v
        var vh = hello
        vh.role = .video
        v.onState = { [weak v] state in
            if case .ready = state { v?.sendJSON(.hello, vh) }
        }
        v.onFrame = { [weak self] f in self?.handleVideo(f) }
        v.onClose = { [weak self] e in
            self?.close(reason: e.map { L("Video: %@", Self.describe($0)) } ?? L("Videoverbindung beendet."))
        }
        v.start()
        renderer.requestKeyframe = { [weak self, weak v] in
            v?.send(.requestKeyframe, Data())
            _ = self
        }
        startAudio()
    }

    /// Sound is optional: if this connection fails, the session keeps running without it.
    private func startAudio() {
        guard audio == nil, let player = audioPlayer else { return }
        let a = FramedConnection(NWConnection(to: endpoint, using: TafelNetwork.parameters(psk: key, identity: identity, channel: .audio, link: dataLink)), queue: queue)
        audio = a
        var ah = hello
        ah.role = .audio
        a.onState = { [weak a] state in
            if case .ready = state { a?.sendJSON(.hello, ah) }
        }
        a.onFrame = { f in
            if f.type == .audioChunk, let chunk = try? AudioChunk(decoding: f.payload) { player.play(chunk) }
        }
        a.onClose = { [weak self] _ in self?.audio = nil }
        a.start()
    }

    private func handleControl(_ f: Frame) {
        switch f.type {
        case .settingsPatch:
            if let o = try? JSONSerialization.jsonObject(with: f.payload) as? [String: Any] { onSettingsPatch?(o) }
        case .rekey:
            if let g = try? JSONWire.decode(PairGrant.self, f.payload), g.keyID != nil { onRekey?(g) }
        case .appInfo:
            if let a = try? JSONWire.decode(AppInfo.self, f.payload) { onAppInfo?(a) }
        case .pluginActions:
            if let l = try? JSONWire.decode([PluginActionInfo].self, f.payload) { onPluginActions?(l) }
        case .toast:
            if let t = try? JSONWire.decode(Toast.self, f.payload) { onToast?(t) }
        case .clipboard:
            if let c = try? ClipboardItem(decoding: f.payload) { onClipboard?(c) }
        case .screenshot:
            onScreenshot?(f.payload)
        case .sourceList:
            if let l = try? JSONWire.decode(SourceList.self, f.payload) { onSourceList?(l) }
        case .hostInfo:
            guard let info = try? JSONWire.decode(HostInfo.self, f.payload) else { return }
            if !connected {
                connected = true
                // An extra (tablet) iPad gets no picture.
                if info.secondary != true { startVideo() }
                startPings()
                onConnected?()
            }
            onHostInfo?(info)
        case .pong:
            guard let p = try? Pong(decoding: f.payload) else { return }
            lastPong = Date()
            let now = Date().timeIntervalSince1970
            let sample = now - p.clientTime
            rtt = rtt == 0 ? sample : rtt * 0.7 + sample * 0.3
            let offset = p.hostTime - (p.clientTime + sample / 2)
            clockOffset = clockOffset.map { $0 * 0.8 + offset * 0.2 } ?? offset
        case .error:
            let msg = (try? JSONWire.decode(ErrorMessage.self, f.payload))?.message ?? L("Fehler vom Mac.")
            close(reason: msg)
        default:
            break
        }
    }

    private func handleVideo(_ f: Frame) {
        switch f.type {
        case .videoFormat:
            if let fmt = try? VideoFormat(decoding: f.payload) { renderer.handle(format: fmt) }
        case .videoFrame:
            guard let frame = try? VideoFrame(decoding: f.payload) else { return }
            framesThisSecond += 1
            if let off = clockOffset {
                let age = Date().timeIntervalSince1970 - (frame.captureTime - off)
                frameAges.append(age)
            }
            renderer.handle(frame: frame)
        case .paletteFrame:
            onPalette?(f.payload)
        default:
            break
        }
    }

    private func startPings() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        lastPong = Date()
        t.schedule(deadline: .now(), repeating: 0.5)
        t.setEventHandler { [weak self] in
            guard let self, let c = self.control else { return }
            if Date().timeIntervalSince(self.lastPong) > Self.deadAfter {
                self.close(reason: L("Keine Antwort vom Mac – Verbindung unterbrochen."))
                return
            }
            c.send(.ping, Ping(clientTime: Date().timeIntervalSince1970).encoded())
            let ages = self.frameAges
            self.frameAges.removeAll(keepingCapacity: true)
            let medianAge = ages.isEmpty ? nil : ages.sorted()[ages.count / 2] * 1000
            let timing = Timing(rttMs: self.rtt * 1000, frameAgeMs: medianAge, fps: Double(self.framesThisSecond) * 2, link: self.linkDescription)
            self.framesThisSecond = 0
            self.onTiming?(timing)
        }
        t.resume()
        pingTimer = t
    }

    // MARK: Sending (any thread)

    func send(_ pen: PenSample) {
        if pen.phase == .down { Session.strokesSent.add() }
        control?.send(.pen, pen.encoded())
    }

    /// Pencil strokes sent since the counter was reset (session summary).
    static let strokesSent = StrokeCounter()
    func send(_ scroll: ScrollEvent) { control?.send(.scroll, scroll.encoded()) }
    func send(_ shortcut: Shortcut) { control?.send(.shortcut, shortcut.encoded()) }
    func send(_ key: KeyEvent) { control?.send(.key, key.encoded()) }
    func send(_ mouse: MouseEvent) { control?.send(.mouse, mouse.encoded()) }
    func send(_ gesture: GestureEvent) { control?.sendJSON(.gesture, gesture) }
    func send(_ selection: SourceSelection) { control?.sendJSON(.selectSource, selection) }
    func send(charKey: CharKeyEvent) { control?.sendJSON(.charKey, charKey) }
    func runPluginAction(_ id: String) { control?.sendJSON(.runPluginAction, RunPluginAction(id: id)) }

    /// Settings snapshot for the developer API on the Mac (sent once ready, and on change).
    func send(settings: InputSettings, quality: StreamQuality) {
        queue.async { [self] in
            guard controlReady,
                  let s = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)),
                  let q = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(quality)),
                  let d = try? JSONSerialization.data(withJSONObject: ["settings": s, "quality": q]) else { return }
            control?.send(.clientSettings, d)
        }
    }
    func send(text: String) { control?.send(.text, TextInput(text).encoded()) }
    func send(clipboard: ClipboardItem) { control?.send(.clipboard, clipboard.encoded()) }
    func requestClipboard() { control?.send(.requestClipboard, Data()) }
    func requestScreenshot() { control?.send(.requestScreenshot, Data()) }
    func sendPalette(_ m: MouseEvent) { control?.send(.paletteMouse, m.encoded()) }
    func send(_ c: HostCommand) { control?.send(.hostCommand, Data([c.rawValue])) }
    func sendPalette(_ c: PaletteCommand) { control?.send(.paletteCommand, Data([c.rawValue])) }

    func send(config: ClientConfig) {
        queue.async { [self] in
            guard config != lastConfig else { return }
            lastConfig = config
            if controlReady { control?.sendJSON(.clientConfig, config) }
        }
    }

    func close(reason: String? = nil) {
        queue.async { [self] in
            guard !closed else { return }
            closed = true
            pingTimer?.cancel()
            pingTimer = nil
            control?.onClose = nil
            video?.onClose = nil
            audio?.onClose = nil
            control?.cancel()
            video?.cancel()
            audio?.cancel()
            audioPlayer?.stop()
            renderer.requestKeyframe = nil
            onClosed?(reason)
        }
    }

    static func describe(_ e: Error) -> String {
        if let nw = e as? NWError, case .tls(let status) = nw {
            return L("Verschlüsselung abgelehnt (%d). Ist das iPad noch mit diesem Mac gekoppelt?", Int(status))
        }
        return e.localizedDescription
    }
}

/// Short-lived connection to the pairing listener.
final class PairingAttempt: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tafel.client.pair")
    private var conn: FramedConnection?
    private var done = false

    func run(endpoint: NWEndpoint, code: String, deviceID: String, deviceName: String,
             completion: @escaping (Result<PairGrant, Error>) -> Void) {
        let params = TafelNetwork.parameters(psk: PairingCode.pairingPSK(code: code), identity: PairingCode.pskIdentity, video: false)
        let c = FramedConnection(NWConnection(to: endpoint, using: params), queue: queue)
        conn = c
        // Strong capture on purpose: the attempt keeps itself alive until it finishes, then breaks
        // the cycle by dropping the connection.
        let finish: (Result<PairGrant, Error>) -> Void = { r in
            guard !self.done else { return }
            self.done = true
            self.conn?.onClose = nil
            self.conn?.onFrame = nil
            self.conn?.cancel()
            self.conn = nil
            DispatchQueue.main.async { completion(r) }
        }
        c.onState = { [weak c] state in
            if case .ready = state {
                c?.sendJSON(.hello, Hello(role: .pair, deviceID: deviceID, deviceName: deviceName))
            }
        }
        c.onFrame = { f in
            if f.type == .pairGrant, let g = try? JSONWire.decode(PairGrant.self, f.payload) {
                finish(.success(g))
            }
        }
        c.onClose = { e in finish(.failure(PairingError.rejected(e.map(Session.describe) ?? L("Verbindung beendet")))) }
        c.start()
        queue.asyncAfter(deadline: .now() + 10) { finish(.failure(PairingError.timeout)) }
    }
}

enum PairingError: LocalizedError {
    case rejected(String), timeout, badCode
    var errorDescription: String? {
        switch self {
        case .rejected: return L("Kopplung fehlgeschlagen – Code falsch oder abgelaufen.")
        case .timeout: return L("Kopplung: Zeitüberschreitung.")
        case .badCode: return L("Der Code hat 12 Zeichen (z. B. ABCD-EFGH-JKMN).")
        }
    }
}

final class StrokeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.withLock { n += 1 } }
    func reset() { lock.withLock { n = 0 } }
    var value: Int { lock.withLock { n } }
}
