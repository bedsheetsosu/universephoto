import Foundation
import Network
import TafelKit

/// Two Bonjour listeners:
///  - `_tafel._tcp`: regular sessions, TLS-PSK with the long-term host key.
///  - `_tafelpair._tcp`: only while the user has opened the pairing window, TLS-PSK derived from
///    the one-time code. Hands out the host key once, then closes.
/// One iPad session with the picture: a control connection (input, timing) and a video connection,
/// so video bursts never delay Pencil packets behind them (no head-of-line blocking). Further iPads
/// connect as "extra" tablets: control connection only (input, no video).
final class HostServer {
    let queue = DispatchQueue(label: "tafel.host.net", qos: .userInteractive)

    var hostID = ""
    var hostName = ""
    /// Bonjour advertisement; disabled in integration tests.
    var advertise = true
    /// Also listen/advertise on Äbbl peer-to-peer Wi-Fi (AWDL). Off by default: AWDL costs
    /// Wi-Fi latency. Only needed when Mac and iPad share no network and no cable.
    var peerToPeer = false
    var sourceDescription: () -> String = { "" }

    // Callbacks, invoked on `queue`.
    var onClientConfig: ((ClientConfig) -> Void)?
    var onSelectSource: ((SourceSelection) -> Void)?
    var onRunPluginAction: ((String) -> Void)?
    var onCharKey: ((CharKeyEvent) -> Void)?
    var onPen: ((PenSample) -> Void)?
    /// Clipboard sent by an iPad (main thread). Only happens when the user taps it on the iPad.
    var onClipboard: ((ClipboardItem) -> Void)?
    /// Reads the Mac clipboard for an iPad that asked for it (main thread).
    var clipboardProvider: (() -> ClipboardItem)?
    /// Takes a full-resolution screenshot of the streamed source and calls back with PNG/JPEG
    /// data (nil = failed). Called on the main thread.
    var screenshotProvider: ((@escaping (Data?) -> Void) -> Void)?
    /// Pencil samples of extra (tablet) iPads – mapped onto a whole display, not the stream.
    var onExtraPen: ((PenSample) -> Void)?
    /// Names of the extra (tablet) iPads connected.
    var onExtrasChanged: (([String]) -> Void)?
    var onScroll: ((ScrollEvent) -> Void)?
    var onShortcut: ((Shortcut) -> Void)?
    var onKey: ((KeyEvent) -> Void)?
    var onMouse: ((MouseEvent) -> Void)?
    var onPaletteMouse: ((MouseEvent) -> Void)?
    var onPaletteCommand: ((PaletteCommand) -> Void)?
    var onHostCommand: ((HostCommand) -> Void)?
    /// iPad settings snapshot as JSON {settings, quality} (developer API).
    var onClientSettings: (([String: Any]) -> Void)?
    var onGesture: ((GestureEvent) -> Void)?
    var onText: ((String) -> Void)?
    var onRequestKeyframe: (() -> Void)?
    var onVideoConnected: (() -> Void)?
    /// Device name (nil = session ended) and the path it uses ("USB-Kabel (en8)", …).
    var onSession: ((String?, String) -> Void)?
    var onPaired: ((String) -> Void)?
    /// The list of paired iPads changed (pairing, an older pairing got its own key).
    var onDevicesChanged: (() -> Void)?
    /// Keys the main listener accepts (one per iPad plus the shared key of older pairings).
    var keyStore: DeviceKeyStore!
    var onStatus: ((String) -> Void)?
    /// Listener ready (true) or not (false) – a state, independent of the shown language.
    var onReady: ((Bool) -> Void)?

    private var listener: NWListener?
    private var pairingListener: NWListener?
    private var pending: [ObjectIdentifier: FramedConnection] = [:]
    private var control: FramedConnection?
    private var sessionDeviceID: String?
    private var extras: [ObjectIdentifier: (fc: FramedConnection, deviceID: String, name: String)] = [:]

    private func extrasChanged() {
        let names = extras.values.map(\.name).sorted()
        onExtrasChanged?(names)
    }

    private let videoLock = NSLock()
    private var video: FramedConnection?
    private var audio: FramedConnection?

    // MARK: Main listener

    /// (Re)starts the main listener with the current keys. Open connections are not affected.
    func start() {
        queue.async { [self] in
            listener?.cancel()
            do {
                let l = try NWListener(using: TafelNetwork.parameters(psks: keyStore.psks(), channel: .control,
                                                                    link: peerToPeer ? .any : .noPeerToPeer))
                if advertise {
                    l.service = NWListener.Service(name: hostName, type: TafelNetwork.serviceType,
                                                   txtRecord: NWTXTRecord([TafelNetwork.txtHostIDKey: hostID]))
                }
                l.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        self?.onReady?(true)
                        self?.onStatus?(L("Bereit (Port %d)", Int(l.port?.rawValue ?? 0)))
                    case .failed(let e):
                        self?.onReady?(false)
                        self?.onStatus?(L("Listener-Fehler: %@", e.localizedDescription))
                    case .waiting(let e):
                        self?.onReady?(false)
                        self?.onStatus?(L("Wartet: %@", e.localizedDescription))
                    default: break
                    }
                }
                l.newConnectionHandler = { [weak self] c in self?.accept(c) }
                l.start(queue: queue)
                listener = l
            } catch {
                onStatus?(L("Listener konnte nicht starten: %@", error.localizedDescription))
            }
        }
    }

    /// Ends the connections of one iPad (after unpairing it).
    func disconnect(deviceID: String) {
        queue.async { [self] in
            if sessionDeviceID == deviceID {
                control?.cancel()
                currentVideo()?.cancel()
                currentAudio()?.cancel()
            }
            for e in extras.values where e.deviceID == deviceID { e.fc.cancel() }
        }
    }

    /// An iPad said hello on the main listener: note it, or move it off the shared key (queue).
    private func handleKeys(_ hello: Hello, _ fc: FramedConnection) {
        if let id = hello.keyID {
            keyStore.touch(id: id, name: hello.deviceName)
            onDevicesChanged?()   // "last connected" in the list
            return
        }
        let issued = keyStore.issueForLegacy(name: hello.deviceName, deviceID: hello.deviceID)
        fc.sendJSON(.rekey, PairGrant(hostID: hostID, hostName: hostName, keyBase64: issued.key.base64EncodedString(), keyID: issued.id))
        onDevicesChanged?()
        // The listener learns the new key a moment later; open connections are not affected.
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }

    /// Drop the current session (e.g. after unpairing).
    func disconnectSession() {
        queue.async { [self] in
            control?.cancel()
            currentVideo()?.cancel()
            currentAudio()?.cancel()
            for e in extras.values { e.fc.cancel() }
        }
    }

    private func accept(_ c: NWConnection) {
        let fc = FramedConnection(c, queue: queue)
        let id = ObjectIdentifier(fc)
        pending[id] = fc
        fc.onFrame = { [weak self, weak fc] frame in
            guard let self, let fc else { return }
            guard frame.type == .hello, let hello = try? JSONWire.decode(Hello.self, frame.payload) else {
                fc.cancel(); return
            }
            self.pending[id] = nil
            self.promote(fc, hello: hello)
        }
        fc.onClose = { [weak self] _ in self?.pending[id] = nil }
        fc.start()
        // Connections that never say hello are dropped.
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak fc] in
            guard let self, let fc, self.pending[id] != nil else { return }
            self.pending[id] = nil
            fc.cancel()
        }
    }

    private func promote(_ fc: FramedConnection, hello: Hello) {
        guard hello.protocolVersion == tafelProtocolVersion else {
            fc.sendJSON(.error, ErrorMessage(message: L("Protokollversion %d wird nicht unterstützt (Mac: %d). Bitte beide Apps aktualisieren.", Int(hello.protocolVersion), Int(tafelProtocolVersion))))
            queue.asyncAfter(deadline: .now() + 0.5) { fc.cancel() }
            return
        }
        switch hello.role {
        case .control:
            // Another iPad already has the picture: this one becomes an extra tablet.
            if control != nil, let current = sessionDeviceID, current != hello.deviceID {
                promoteExtra(fc, hello: hello)
                return
            }
            if let old = control, old !== fc { old.onClose = nil; old.cancel(); currentVideo()?.cancel(); currentAudio()?.cancel() }
            control = fc
            sessionDeviceID = hello.deviceID
            handleKeys(hello, fc)
            fc.onFrame = { [weak self] f in self?.handleControl(f, from: fc) }
            fc.onClose = { [weak self, weak fc] _ in
                guard let self, self.control === fc else { return }
                self.control = nil
                self.sessionDeviceID = nil
                self.currentVideo()?.cancel()
                self.currentAudio()?.cancel()
                self.onSession?(nil, "")
            }
            fc.sendJSON(.hostInfo, HostInfo(hostID: hostID, hostName: hostName, sourceDescription: sourceDescription()))
            if let frontApp { fc.sendJSON(.appInfo, frontApp) }
            if let sourceList { fc.sendJSON(.sourceList, sourceList) }
            if let pluginActions { fc.sendJSON(.pluginActions, pluginActions) }
            onSession?(hello.deviceName, fc.connection.linkDescription)
        case .video:
            guard hello.deviceID == sessionDeviceID else { fc.cancel(); return }
            let old: FramedConnection? = videoLock.withLock { let o = video; video = fc; return o }
            if let old, old !== fc { old.onClose = nil; old.cancel() }
            fc.onFrame = { [weak self] f in if f.type == .requestKeyframe { self?.onRequestKeyframe?() } }
            fc.onClose = { [weak self, weak fc] _ in
                guard let self else { return }
                self.videoLock.withLock { if self.video === fc { self.video = nil } }
            }
            onVideoConnected?()
        case .audio:
            guard hello.deviceID == sessionDeviceID else { fc.cancel(); return }
            let old: FramedConnection? = videoLock.withLock { let o = audio; audio = fc; return o }
            if let old, old !== fc { old.onClose = nil; old.cancel() }
            fc.onFrame = { _ in }
            fc.onClose = { [weak self, weak fc] _ in
                guard let self else { return }
                self.videoLock.withLock { if self.audio === fc { self.audio = nil } }
            }
        case .pair:
            fc.cancel() // pairing only on the pairing listener
        }
    }

    private func promoteExtra(_ fc: FramedConnection, hello: Hello) {
        // Same iPad reconnecting as extra: replace its old connection.
        for (k, e) in extras where e.deviceID == hello.deviceID { e.fc.onClose = nil; e.fc.cancel(); extras[k] = nil }
        let id = ObjectIdentifier(fc)
        extras[id] = (fc, hello.deviceID, hello.deviceName)
        handleKeys(hello, fc)
        fc.onFrame = { [weak self] f in self?.handleControl(f, from: fc, extra: true) }
        fc.onClose = { [weak self] _ in
            guard let self else { return }
            self.extras[id] = nil
            self.extrasChanged()
        }
        fc.sendJSON(.hostInfo, HostInfo(hostID: hostID, hostName: hostName, sourceDescription: sourceDescription(), secondary: true))
        if let frontApp { fc.sendJSON(.appInfo, frontApp) }
        if let pluginActions { fc.sendJSON(.pluginActions, pluginActions) }
        extrasChanged()
    }

    /// Sends a JSON message to the main iPad and every extra tablet iPad (queue).
    private func broadcast<T: Encodable>(_ type: MessageType, _ value: T) {
        control?.sendJSON(type, value)
        for e in extras.values { e.fc.sendJSON(type, value) }
    }

    private func handleControl(_ f: Frame, from fc: FramedConnection, extra: Bool = false) {
        switch f.type {
        case .pen:
            if let s = try? PenSample(decoding: f.payload) { if extra { onExtraPen?(s) } else { onPen?(s) } }
        case .clientConfig where extra, .clientSettings where extra, .selectSource where extra, .requestKeyframe where extra:
            break   // extras don't steer the picture or the settings snapshot
        case .scroll:
            if let s = try? ScrollEvent(decoding: f.payload) { onScroll?(s) }
        case .shortcut:
            if let s = try? Shortcut(decoding: f.payload) { onShortcut?(s) }
        case .mouse:
            if let m = try? MouseEvent(decoding: f.payload) { onMouse?(m) }
        case .paletteMouse:
            if let m = try? MouseEvent(decoding: f.payload) { onPaletteMouse?(m) }
        case .hostCommand:
            if let b = f.payload.first, let c = HostCommand(rawValue: b) {
                DispatchQueue.main.async { [weak self] in self?.onHostCommand?(c) }
            }
        case .paletteCommand:
            if let b = f.payload.first, let c = PaletteCommand(rawValue: b) {
                DispatchQueue.main.async { [weak self] in self?.onPaletteCommand?(c) }
            }
        case .clientSettings:
            if let o = try? JSONSerialization.jsonObject(with: f.payload) as? [String: Any] { onClientSettings?(o) }
        case .gesture:
            if let g = try? JSONWire.decode(GestureEvent.self, f.payload) { onGesture?(g) }
        case .key:
            if let k = try? KeyEvent(decoding: f.payload) { onKey?(k) }
        case .text:
            if let t = try? TextInput(decoding: f.payload) { onText?(t.text) }
        case .ping:
            if let p = try? Ping(decoding: f.payload) {
                fc.send(.pong, Pong(clientTime: p.clientTime, hostTime: Date().timeIntervalSince1970).encoded())
            }
        case .clientConfig:
            if let c = try? JSONWire.decode(ClientConfig.self, f.payload) { onClientConfig?(c) }
        case .requestKeyframe:
            onRequestKeyframe?()
        case .charKey:
            if let k = try? JSONWire.decode(CharKeyEvent.self, f.payload) { onCharKey?(k) }
        case .runPluginAction:
            if let a = try? JSONWire.decode(RunPluginAction.self, f.payload) { onRunPluginAction?(a.id) }
        case .selectSource:
            if let s = try? JSONWire.decode(SourceSelection.self, f.payload) { onSelectSource?(s) }
        case .clipboard:
            if let item = try? ClipboardItem(decoding: f.payload) {
                DispatchQueue.main.async { [weak self] in self?.onClipboard?(item) }
            }
        case .requestScreenshot:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let provider = self.screenshotProvider else { self.queue.async { fc.send(.screenshot, Data()) }; return }
                provider { data in self.queue.async { fc.send(.screenshot, data ?? Data()) } }
            }
        case .requestClipboard:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let item = self.clipboardProvider?() ?? ClipboardItem(kind: .empty)
                self.queue.async { fc.send(.clipboard, item.encoded()) }
            }
        default:
            break
        }
    }

    /// Last front app, also sent to a newly connected iPad.
    private var frontApp: AppInfo?

    /// Whether an iPad session is connected.
    var hasSession: Bool { queue.sync { control != nil } }

    /// Sends a settings patch {settings?, quality?} to the iPad (developer Control API).
    func sendSettingsPatch(_ patch: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: patch) else { return false }
        return queue.sync {
            guard let c = control else { return false }
            c.send(.settingsPatch, data)
            return true
        }
    }

    /// Actions of running plugins, also sent to a newly connected iPad.
    private var pluginActions: [PluginActionInfo]?

    func sendPluginActions(_ list: [PluginActionInfo]) {
        queue.async { [self] in
            guard list != pluginActions else { return }
            pluginActions = list
            broadcast(.pluginActions, list)
        }
    }

    func sendToast(_ t: Toast) {
        queue.async { [self] in broadcast(.toast, t) }
    }

    /// Last source list, also sent to a newly connected iPad.
    private var sourceList: SourceList?

    func sendSourceList(_ list: SourceList) {
        queue.async { [self] in
            guard list != sourceList else { return }
            sourceList = list
            control?.sendJSON(.sourceList, list)
        }
    }

    func sendAppInfo(_ info: AppInfo) {
        queue.async { [self] in
            frontApp = info
            broadcast(.appInfo, info)
        }
    }

    func sendHostInfo() {
        queue.async { [self] in
            control?.sendJSON(.hostInfo, HostInfo(hostID: hostID, hostName: hostName, sourceDescription: sourceDescription()))
        }
    }

    // MARK: Video

    private func currentVideo() -> FramedConnection? { videoLock.withLock { video } }

    var hasVideo: Bool { currentVideo() != nil }
    var videoBacklog: Int { currentVideo()?.pendingBytes ?? 0 }

    /// Thread-safe; called from the encoder callback.
    func sendVideo(format: VideoFormat?, frame: VideoFrame) {
        guard let v = currentVideo() else { return }
        if let format { v.send(.videoFormat, format.encoded()) }
        v.send(.videoFrame, frame.encoded())
    }

    /// Thread-safe. Palette pictures share the video connection (never delays pen input);
    /// skipped while the video is backed up.
    func sendPalette(_ jpeg: Data) {
        guard let v = currentVideo(), v.pendingBytes < 4 * 1024 * 1024 else { return }
        v.send(.paletteFrame, jpeg)
    }

    // MARK: Audio

    private func currentAudio() -> FramedConnection? { videoLock.withLock { audio } }

    /// Thread-safe. Drops chunks while more than ~80 ms of audio are still queued on the socket,
    /// so a network hiccup costs a short gap instead of a growing delay.
    func sendAudio(_ chunk: AudioChunk) {
        guard let a = currentAudio() else { return }
        let maxBacklog = chunk.sampleRate * chunk.channels * 2 * 80 / 1000
        guard a.pendingBytes < maxBacklog else { return }
        a.send(.audioChunk, chunk.encoded())
    }

    var mainPort: UInt16? { queue.sync { listener?.port?.rawValue } }
    var pairingPort: UInt16? { queue.sync { pairingListener?.port?.rawValue } }

    // MARK: Pairing

    /// Opens the pairing listener; a right code gets `grantKey` (prepared in the key store and
    /// already accepted by the main listener).
    func startPairing(code: String, grantKey: Data, keyID: String) {
        queue.async { [self] in
            pairingListener?.cancel()
            do {
                let params = TafelNetwork.parameters(psk: PairingCode.pairingPSK(code: code), identity: PairingCode.pskIdentity,
                                                    channel: .control, link: peerToPeer ? .any : .noPeerToPeer)
                let l = try NWListener(using: params)
                if advertise {
                    l.service = NWListener.Service(name: hostName, type: TafelNetwork.pairingServiceType,
                                                   txtRecord: NWTXTRecord([TafelNetwork.txtHostIDKey: hostID]))
                }
                l.newConnectionHandler = { [weak self] c in self?.acceptPairing(c, key: grantKey, keyID: keyID) }
                l.start(queue: queue)
                pairingListener = l
            } catch {
                onStatus?(L("Kopplung konnte nicht starten: %@", error.localizedDescription))
            }
        }
    }

    func stopPairing() {
        queue.async { [self] in
            pairingListener?.cancel()
            pairingListener = nil
        }
    }

    private func acceptPairing(_ c: NWConnection, key: Data, keyID: String) {
        let fc = FramedConnection(c, queue: queue)
        let id = ObjectIdentifier(fc)
        pending[id] = fc
        fc.onFrame = { [weak self, weak fc] frame in
            guard let self, let fc else { return }
            // Reaching this point means the TLS handshake with the code-derived key succeeded.
            guard frame.type == .hello, let hello = try? JSONWire.decode(Hello.self, frame.payload), hello.role == .pair else {
                fc.cancel(); return
            }
            fc.sendJSON(.pairGrant, PairGrant(hostID: self.hostID, hostName: self.hostName, keyBase64: key.base64EncodedString(), keyID: keyID))
            self.keyStore.completePairing(id: keyID, name: hello.deviceName, deviceID: hello.deviceID)
            self.pairingListener?.cancel()
            self.pairingListener = nil
            self.onPaired?(hello.deviceName)
            self.onDevicesChanged?()
            self.queue.asyncAfter(deadline: .now() + 2) { fc.cancel(); self.pending[id] = nil }
        }
        fc.onClose = { [weak self] _ in self?.pending[id] = nil }
        fc.start()
    }
}
