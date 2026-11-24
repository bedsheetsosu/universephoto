import Foundation

public let tafelProtocolVersion = 2

/// One byte message tag. Low-frequency messages are JSON, high-frequency ones binary.
public enum MessageType: UInt8, Sendable {
    // JSON
    case hello = 0x01          // client -> host, first frame on every connection
    case hostInfo = 0x02       // host -> client
    case clientConfig = 0x03   // client -> host
    case pairGrant = 0x04      // host -> client, only on the pairing listener
    case error = 0x05          // host -> client
    case appInfo = 0x06        // host -> client: app in front on the Mac
    case clientSettings = 0x07 // client -> host: JSON {settings, quality} (for the developer API)
    case settingsPatch = 0x08  // host -> client: JSON {settings?, quality?} deep-merged into the iPad's settings
    case sourceList = 0x09     // host -> client: JSON SourceList (what the Mac can stream, for the iPad's source menu)
    case selectSource = 0x0A   // client -> host: JSON SourceSelection
    case pluginActions = 0x0B  // host -> client: JSON [PluginActionInfo] (actions plugins offer)
    case runPluginAction = 0x0C // client -> host: JSON {id}
    case toast = 0x0D          // host -> client: JSON Toast (short message shown on the iPad)
    case clipboard = 0x0E      // both ways: ClipboardItem (only when the user asks, never automatic)
    case requestClipboard = 0x0F // client -> host: empty, host answers with .clipboard
    // binary input
    case pen = 0x10
    case scroll = 0x11
    case mouse = 0x12          // trackpad / mouse pointer
    case gesture = 0x13        // client -> host: JSON GestureEvent (informational, for the developer API)
    case requestScreenshot = 0x16 // client -> host: empty, host answers with .screenshot
    case screenshot = 0x17     // host -> client: PNG or JPEG of the streamed source at full resolution (empty = failed)
    case paletteFrame = 0x18   // host -> client, video connection: JPEG of the palette area (empty = no palette)
    case paletteMouse = 0x19   // client -> host: MouseEvent, x/y normalised inside the palette area
    case paletteCommand = 0x1A // client -> host: u8 PaletteCommand
    case hostCommand = 0x1B    // client -> host: u8 HostCommand
    case rekey = 0x24          // host -> client: JSON PairGrant with the iPad's own key (moves an older pairing off the shared key)
    case shortcut = 0x20
    case key = 0x21            // hardware keyboard key down/up (HID usage)
    case text = 0x22           // on-screen keyboard text (UTF-8)
    case charKey = 0x23        // client -> host: JSON CharKeyEvent (hold a key by character, tablet keys)
    // timing
    case ping = 0x30
    case pong = 0x31
    // video
    case videoFormat = 0x40
    case videoFrame = 0x41
    case requestKeyframe = 0x42
    // audio
    case audioChunk = 0x50
}

public struct Frame: Sendable {
    public var type: MessageType
    public var payload: Data
    public init(type: MessageType, payload: Data) {
        self.type = type
        self.payload = payload
    }
}

/// `[u8 type][u32 LE length][payload]`
public enum FrameCodec {
    public static let headerSize = 5
    public static let maxPayload = 64 * 1024 * 1024

    public static func encode(_ type: MessageType, _ payload: Data) -> Data {
        var w = ByteWriter(capacity: headerSize + payload.count)
        w.u8(type.rawValue)
        w.u32(UInt32(payload.count))
        w.rest(payload)
        return w.data
    }

    /// Returns raw type byte and payload length.
    public static func parseHeader(_ header: Data) throws -> (type: UInt8, length: Int) {
        var r = ByteReader(header)
        let t = try r.u8()
        let n = Int(try r.u32())
        guard n <= maxPayload else { throw WireError.tooLarge }
        return (t, n)
    }

    /// Splits a byte stream into frames; returns frames and the unconsumed tail. Used by tests
    /// and as a reference for the streaming receiver.
    public static func split(_ stream: Data) throws -> (frames: [Frame], rest: Data) {
        var frames: [Frame] = []
        var cursor = stream.startIndex
        while stream.endIndex - cursor >= headerSize {
            let (t, n) = try parseHeader(Data(stream[cursor..<(cursor + headerSize)]))
            guard stream.endIndex - cursor - headerSize >= n else { break }
            let start = cursor + headerSize
            if let type = MessageType(rawValue: t) {
                frames.append(Frame(type: type, payload: Data(stream[start..<(start + n)])))
            }
            cursor = start + n
        }
        return (frames, Data(stream[cursor..<stream.endIndex]))
    }
}

// MARK: - JSON messages

public enum ConnectionRole: String, Codable, Sendable {
    case control, video, audio, pair
}

public struct Hello: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var role: ConnectionRole
    public var deviceID: String
    public var deviceName: String
    /// Which key the iPad connects with (nil = the shared host key of pairings made before
    /// every iPad got its own key).
    public var keyID: String?
    public init(protocolVersion: Int = tafelProtocolVersion, role: ConnectionRole, deviceID: String, deviceName: String,
                keyID: String? = nil) {
        self.protocolVersion = protocolVersion
        self.role = role
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.keyID = keyID
    }
}

public struct HostInfo: Codable, Equatable, Sendable {
    public var hostID: String
    public var hostName: String
    public var protocolVersion: Int
    /// Human-readable description of what is being captured.
    public var sourceDescription: String
    /// Another iPad already shows the picture: this one works as a tablet (input only, no video).
    public var secondary: Bool?
    public init(hostID: String, hostName: String, protocolVersion: Int = tafelProtocolVersion, sourceDescription: String,
                secondary: Bool? = nil) {
        self.hostID = hostID
        self.hostName = hostName
        self.protocolVersion = protocolVersion
        self.sourceDescription = sourceDescription
        self.secondary = secondary
    }
}

public enum VideoCodec: String, Codable, CaseIterable, Sendable {
    case h264, hevc
}

public struct StreamQuality: Codable, Equatable, Sendable {
    public var codec: VideoCodec
    public var bitrateMbps: Double
    public var fps: Int
    /// 1.0 = native iPad pixels, 0.5 = half resolution per axis.
    public var resolutionScale: Double
    /// Also capture and send the Mac's sound.
    public var audio: Bool
    /// Lower the bitrate automatically when the connection cannot keep up, raise it again after.
    public var adaptive: Bool
    /// Send the captured pixels unscaled (e.g. 2952×2052 for a "more space" second
    /// screen) and let the iPad scale them down when showing them. More bitrate and encoder load.
    public var fullSource: Bool
    /// 10 bits per channel (HEVC Main10) instead of 8: four times as many colour steps, no banding
    /// in soft gradients. Only with HEVC; H.264 always stays 8-bit.
    public var tenBit: Bool

    public init(codec: VideoCodec = .h264, bitrateMbps: Double = 30, fps: Int = 60, resolutionScale: Double = 1.0, audio: Bool = true,
                adaptive: Bool = true, fullSource: Bool = true, tenBit: Bool = true) {
        self.fullSource = fullSource
        self.tenBit = tenBit
        self.codec = codec
        self.bitrateMbps = bitrateMbps
        self.fps = fps
        self.resolutionScale = resolutionScale
        self.audio = audio
        self.adaptive = adaptive
    }

    private enum CodingKeys: String, CodingKey { case codec, bitrateMbps, fps, resolutionScale, audio, adaptive, fullSource, tenBit }

    /// Tolerates settings saved by older versions (missing keys get defaults).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StreamQuality()
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? d.codec
        bitrateMbps = try c.decodeIfPresent(Double.self, forKey: .bitrateMbps) ?? d.bitrateMbps
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? d.fps
        resolutionScale = try c.decodeIfPresent(Double.self, forKey: .resolutionScale) ?? d.resolutionScale
        audio = try c.decodeIfPresent(Bool.self, forKey: .audio) ?? d.audio
        adaptive = try c.decodeIfPresent(Bool.self, forKey: .adaptive) ?? d.adaptive
        fullSource = try c.decodeIfPresent(Bool.self, forKey: .fullSource) ?? d.fullSource
        tenBit = try c.decodeIfPresent(Bool.self, forKey: .tenBit) ?? d.tenBit
    }

    /// What the encoder really uses: 10-bit only exists for HEVC here.
    public var usesTenBit: Bool { tenBit && codec == .hevc }
}

public extension StreamQuality {
    /// Game mode: everything up, nothing that waits (adaptive bitrate stays off so the picture
    /// never gets softer mid-game). The iPad Air shows at most 60 Hz.
    var gameMode: StreamQuality {
        var q = self
        q.fps = 60
        q.resolutionScale = 1
        q.fullSource = true
        q.bitrateMbps = max(q.bitrateMbps, 60)
        q.adaptive = false
        return q
    }
}

public extension StreamQuality {
    /// Heat guard: what the Mac streams at thermal level 0 (cool), 1 ("serious") or 2
    /// ("critical"). Only ever lowers the iPad's settings, never raises them.
    func cooled(level: Int) -> StreamQuality {
        guard level > 0 else { return self }
        var q = self
        q.fps = min(q.fps, 30)
        q.fullSource = false
        q.bitrateMbps = min(q.bitrateMbps, level >= 2 ? 15 : 25)
        if level >= 2 { q.resolutionScale = min(q.resolutionScale, 0.75) }
        return q
    }
}

public struct ClientConfig: Codable, Equatable, Sendable {
    /// Drawable area of the iPad in physical pixels (full screen, current orientation).
    public var viewPixelWidth: Int
    public var viewPixelHeight: Int
    public var quality: StreamQuality
    /// Free-text network diagnostics from the iPad (interfaces it can see). Shown/logged on the
    /// Mac; never affects streaming.
    public var diagnostics: String?
    /// iPad battery 0…1 (nil = unknown) and whether it is charging. Shown in the Mac menu bar.
    public var batteryLevel: Double?
    public var batteryCharging: Bool?
    /// Tablet mode (like a screenless pen tablet): no picture, the iPad's active area maps onto
    /// the whole selected Mac display.
    public var tabletMode: Bool?
    /// Laser pointer: the Pencil draws fading marks over the Mac screen instead of clicking.
    public var laser: Bool?
    /// The iPad is dimmed (nobody looks): the Mac stops capturing until it is not.
    public var paused: Bool?
    /// The iPad's settings profiles and the active one, so the Mac can switch them
    /// (settings patch `{"activateProfile": id}`). Never part of the stream decision.
    public var profiles: [ProfileSummary]?
    public var activeProfile: String?

    public init(viewPixelWidth: Int, viewPixelHeight: Int, quality: StreamQuality, diagnostics: String? = nil,
                batteryLevel: Double? = nil, batteryCharging: Bool? = nil, tabletMode: Bool? = nil, laser: Bool? = nil,
                paused: Bool? = nil, profiles: [ProfileSummary]? = nil, activeProfile: String? = nil) {
        self.paused = paused
        self.profiles = profiles
        self.activeProfile = activeProfile
        self.tabletMode = tabletMode
        self.laser = laser
        self.viewPixelWidth = viewPixelWidth
        self.viewPixelHeight = viewPixelHeight
        self.quality = quality
        self.diagnostics = diagnostics
        self.batteryLevel = batteryLevel
        self.batteryCharging = batteryCharging
    }

    /// Same config, ignoring diagnostics (decides whether the stream must restart).
    public func sameStream(as other: ClientConfig?) -> Bool {
        guard let other else { return false }
        return viewPixelWidth == other.viewPixelWidth && viewPixelHeight == other.viewPixelHeight && quality == other.quality
            && (tabletMode ?? false) == (other.tabletMode ?? false) && (paused ?? false) == (other.paused ?? false)
    }
}

/// One settings profile of the iPad as the Mac sees it.
public struct ProfileSummary: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// A recognised gesture on the iPad, reported in addition to its configured action.
/// Names: tap2, tap3, tap4, swipe3.left/right/up/down, pinch (value = scale factor of this step),
/// rotate (value = degrees of this step), pencil.doubleTap, pencil.squeeze.
public struct GestureEvent: Codable, Equatable, Sendable {
    public var name: String
    public var value: Double
    public init(name: String, value: Double = 0) { self.name = name; self.value = value }
}

/// Deep-merges `patch` into `base` (dictionaries recursively, everything else replaced).
public func deepMerge(_ base: [String: Any], _ patch: [String: Any]) -> [String: Any] {
    var out = base
    for (k, v) in patch {
        if let b = out[k] as? [String: Any], let p = v as? [String: Any] { out[k] = deepMerge(b, p) } else { out[k] = v }
    }
    return out
}

/// Applies a JSON patch to a Codable value via its JSON form (unknown keys are ignored by the
/// tolerant decoders of InputSettings / StreamQuality).
public func applyPatch<T: Codable>(_ value: T, _ patch: [String: Any]) -> T? {
    guard let data = try? JSONEncoder().encode(value),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let merged = try? JSONSerialization.data(withJSONObject: deepMerge(obj, patch)) else { return nil }
    return try? JSONDecoder().decode(T.self, from: merged)
}

/// The app in front on the Mac (for per-app shortcut bars).
/// One choice in the iPad's source menu. `id`: mode name, display ID or window ID as text.
public struct SourceOption: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var available: Bool
    /// Width / height (displays only), e.g. to lock the tablet area to the display's shape.
    public var aspect: Double?
    public init(id: String, title: String, available: Bool = true, aspect: Double? = nil) {
        self.id = id; self.title = title; self.available = available; self.aspect = aspect
    }
}

/// What the Mac can stream. Modes: "display", "second-screen", "region", "window".
public struct SourceList: Codable, Equatable, Sendable {
    public var mode: String
    public var modes: [SourceOption]
    public var displays: [SourceOption]
    public var selectedDisplay: String
    public var windows: [SourceOption]
    public var selectedWindow: String
    public init(mode: String, modes: [SourceOption], displays: [SourceOption], selectedDisplay: String,
                windows: [SourceOption], selectedWindow: String) {
        self.mode = mode; self.modes = modes; self.displays = displays; self.selectedDisplay = selectedDisplay
        self.windows = windows; self.selectedWindow = selectedWindow
    }
}

/// iPad picks a source. All fields optional; `refresh` asks the Mac to re-read its window list first.
public struct SourceSelection: Codable, Equatable, Sendable {
    public var mode: String?
    public var display: String?
    public var window: String?
    public var refresh: Bool?
    public init(mode: String? = nil, display: String? = nil, window: String? = nil, refresh: Bool? = nil) {
        self.mode = mode; self.display = display; self.window = window; self.refresh = refresh
    }
}

/// An action a Mac plugin offers; the iPad can put it on squeeze, the bar, the radial menu, ….
/// `id` is "pluginID/actionID".
public struct PluginActionInfo: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var icon: String?
    public var plugin: String
    public init(id: String, title: String, icon: String? = nil, plugin: String) {
        self.id = id; self.title = title; self.icon = icon; self.plugin = plugin
    }
}

public struct RunPluginAction: Codable, Equatable, Sendable {
    public var id: String
    public init(id: String) { self.id = id }
}

/// Short message from the Mac (e.g. a plugin) shown on the iPad.
/// Clipboard contents copied between iPad and Mac on request. Binary: 1 byte kind, then the data
/// (UTF-8 text or PNG). `.empty` = the other side's clipboard had nothing usable.
public struct ClipboardItem: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case empty = 0, text = 1, png = 2 }
    public static let maxBytes = 32 * 1024 * 1024
    public var kind: Kind
    public var data: Data
    public init(kind: Kind, data: Data = Data()) { self.kind = kind; self.data = data }
    public static func text(_ t: String) -> ClipboardItem { ClipboardItem(kind: .text, data: Data(t.utf8)) }
    public var text: String? { kind == .text ? String(data: data, encoding: .utf8) : nil }

    public func encoded() -> Data { var d = Data([kind.rawValue]); d.append(data); return d }
    public init(decoding d: Data) throws {
        guard let first = d.first, let k = Kind(rawValue: first) else { throw WireError.unknownValue("clipboard kind") }
        guard d.count - 1 <= Self.maxBytes else { throw WireError.tooLarge }
        kind = k
        data = Data(d.dropFirst())
    }
}

public struct Toast: Codable, Equatable, Sendable {
    public var text: String
    public var seconds: Double
    public init(text: String, seconds: Double = 2) { self.text = text; self.seconds = seconds }
}

public struct AppInfo: Codable, Equatable, Sendable {
    public var bundleID: String
    public var name: String
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
}

public struct PairGrant: Codable, Equatable, Sendable {
    public var hostID: String
    public var hostName: String
    /// Base64 of the 32-byte long-term key used as TLS PSK for regular connections.
    public var keyBase64: String
    /// This iPad's own key: connect with the identity `HostKey.deviceIdentity(keyID)`. Without it
    /// the key is the shared host key (identity `HostKey.pskIdentity`).
    public var keyID: String?
    public init(hostID: String, hostName: String, keyBase64: String, keyID: String? = nil) {
        self.hostID = hostID
        self.hostName = hostName
        self.keyBase64 = keyBase64
        self.keyID = keyID
    }

    /// TLS identity that goes with this key.
    public var identity: String { keyID.map(HostKey.deviceIdentity) ?? HostKey.pskIdentity }
}

public struct ErrorMessage: Codable, Equatable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
}

public enum JSONWire {
    public static func encode<T: Encodable>(_ v: T) throws -> Data { try JSONEncoder().encode(v) }
    public static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws -> T { try JSONDecoder().decode(t, from: d) }
}

// MARK: - Binary input messages

/// Trackpad or mouse on the iPad, acting as the Mac's mouse. Position is absolute (where the
/// iPad pointer is over the mirrored image), so pointer and picture always line up.
/// iPad → Mac: small remote controls for the Mac app.
public enum HostCommand: UInt8, Sendable {
    /// Start the time-lapse, or stop it if it is running.
    case toggleTimelapse = 0
}

/// iPad → Mac: what to do with the palette window.
public enum PaletteCommand: UInt8, Sendable {
    /// Forget the palette area.
    case remove = 0
    /// Let the user drag out a new palette area on the Mac.
    case pick = 1
}

public struct MouseEvent: Equatable, Sendable {
    public enum Phase: UInt8, Sendable { case move = 0, down = 1, up = 2, exit = 3 }
    public enum Button: UInt8, Sendable { case left = 0, right = 1 }

    public var phase: Phase
    public var button: Button
    public var x: Float
    public var y: Float

    public init(phase: Phase, button: Button = .left, x: Float, y: Float) {
        self.phase = phase; self.button = button; self.x = x; self.y = y
    }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: 10)
        w.u8(phase.rawValue); w.u8(button.rawValue); w.f32(x); w.f32(y)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        guard let p = Phase(rawValue: try r.u8()) else { throw WireError.unknownValue("mouse phase") }
        guard let b = Button(rawValue: try r.u8()) else { throw WireError.unknownValue("mouse button") }
        phase = p; button = b
        x = try r.f32(); y = try r.f32()
    }
}

public enum PenPhase: UInt8, Sendable {
    case hover = 0      // in range, not touching
    case down = 1
    case move = 2       // touching
    case up = 3
    case enter = 4      // proximity in
    case exit = 5       // proximity out
    case cancel = 6     // touch cancelled by the system: release without a click target guarantee
}

/// A single Pencil sample, already converted to tablet semantics on the iPad.
public struct PenSample: Equatable, Sendable {
    public var phase: PenPhase
    /// Normalized position inside the streamed image, 0...1, origin top-left.
    public var x: Float
    public var y: Float
    /// 0...1 after the pressure curve.
    public var pressure: Float
    /// -1...1 (Wacom-style tilt vector).
    public var tiltX: Float
    public var tiltY: Float
    /// Barrel rotation in degrees (Pencil Pro roll), 0 if unsupported.
    public var rotation: Float
    /// iPad uptime timestamp of the sample (seconds).
    public var timestamp: Double

    public init(phase: PenPhase, x: Float, y: Float, pressure: Float = 0, tiltX: Float = 0, tiltY: Float = 0, rotation: Float = 0, timestamp: Double = 0) {
        self.phase = phase
        self.x = x
        self.y = y
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.rotation = rotation
        self.timestamp = timestamp
    }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: 33)
        w.u8(phase.rawValue)
        w.f32(x); w.f32(y); w.f32(pressure)
        w.f32(tiltX); w.f32(tiltY); w.f32(rotation)
        w.f64(timestamp)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        guard let p = PenPhase(rawValue: try r.u8()) else { throw WireError.unknownValue("pen phase") }
        phase = p
        x = try r.f32(); y = try r.f32(); pressure = try r.f32()
        tiltX = try r.f32(); tiltY = try r.f32(); rotation = try r.f32()
        timestamp = try r.f64()
    }
}

public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = ModifierSet(rawValue: 1 << 0)
    public static let shift = ModifierSet(rawValue: 1 << 1)
    public static let option = ModifierSet(rawValue: 1 << 2)
    public static let control = ModifierSet(rawValue: 1 << 3)

    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// Two-finger scroll, optionally with modifiers (used for zoom-by-scroll).
public struct ScrollEvent: Equatable, Sendable {
    /// Anchor in normalized image coordinates (where the gesture happens).
    public var x: Float
    public var y: Float
    /// Delta in normalized image units (1.0 = full width / height of the capture).
    public var dx: Float
    public var dy: Float
    public var modifiers: ModifierSet

    public init(x: Float, y: Float, dx: Float, dy: Float, modifiers: ModifierSet = []) {
        self.x = x; self.y = y; self.dx = dx; self.dy = dy; self.modifiers = modifiers
    }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: 17)
        w.f32(x); w.f32(y); w.f32(dx); w.f32(dy); w.u8(modifiers.rawValue)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        x = try r.f32(); y = try r.f32(); dx = try r.f32(); dy = try r.f32()
        modifiers = ModifierSet(rawValue: try r.u8())
    }
}

/// A keyboard shortcut described by the *character* it should produce (e.g. "z"), not by a
/// hardware key code, so the Mac can resolve it against its active keyboard layout
/// (QWERTZ vs. QWERTY). Special keys use names: esc, delete, tab, space, return, left, right, up, down.
public struct Shortcut: Codable, Hashable, Sendable {
    public var key: String
    public var modifiers: ModifierSet

    public init(_ key: String, _ modifiers: ModifierSet = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    public var display: String {
        let k: String
        switch key {
        case "esc": k = "esc"
        case "delete": k = "⌫"
        case "tab": k = "⇥"
        case "space": k = L("Leertaste")
        case "return": k = "↩"
        case "left": k = "←"
        case "right": k = "→"
        case "up": k = "↑"
        case "down": k = "↓"
        default: k = key.uppercased()
        }
        return modifiers.symbols + k
    }

    public static let specialKeys: [String: UInt16] = [
        "return": 36, "tab": 48, "space": 49, "delete": 51, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    public func encoded() -> Data {
        var w = ByteWriter(capacity: 8)
        w.u8(modifiers.rawValue)
        w.string(key)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        modifiers = ModifierSet(rawValue: try r.u8())
        key = try r.string()
    }
}

public struct Ping: Equatable, Sendable {
    public var clientTime: Double
    public init(clientTime: Double) { self.clientTime = clientTime }
    public func encoded() -> Data { var w = ByteWriter(); w.f64(clientTime); return w.data }
    public init(decoding d: Data) throws { var r = ByteReader(d); clientTime = try r.f64() }
}

public struct Pong: Equatable, Sendable {
    public var clientTime: Double
    public var hostTime: Double
    public init(clientTime: Double, hostTime: Double) { self.clientTime = clientTime; self.hostTime = hostTime }
    public func encoded() -> Data { var w = ByteWriter(); w.f64(clientTime); w.f64(hostTime); return w.data }
    public init(decoding d: Data) throws { var r = ByteReader(d); clientTime = try r.f64(); hostTime = try r.f64() }
}

// MARK: - Video

public struct VideoFormat: Equatable, Sendable {
    public var codec: VideoCodec
    public var width: Int
    public var height: Int
    /// H.264: [SPS, PPS]; HEVC: [VPS, SPS, PPS]. Raw NAL units without start codes.
    public var parameterSets: [Data]
    /// Picture is in Display P3 (wide colour). Lets the iPad colour-manage it correctly.
    public var displayP3: Bool
    /// Tone curve is sRGB (what macOS captures), not BT.709. False for hosts before 0.8,
    /// which tagged BT.709 and so showed slightly lifted shadows on the iPad.
    public var sRGBTransfer: Bool

    public init(codec: VideoCodec, width: Int, height: Int, parameterSets: [Data], displayP3: Bool = false, sRGBTransfer: Bool = false) {
        self.codec = codec; self.width = width; self.height = height; self.parameterSets = parameterSets
        self.displayP3 = displayP3
        self.sRGBTransfer = sRGBTransfer
    }

    public func encoded() -> Data {
        var w = ByteWriter()
        w.u8(codec == .h264 ? 0 : 1)
        w.u32(UInt32(width)); w.u32(UInt32(height))
        w.u8(UInt8(parameterSets.count))
        for p in parameterSets { w.blob(p) }
        w.bool(displayP3)
        w.bool(sRGBTransfer)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        switch try r.u8() {
        case 0: codec = .h264
        case 1: codec = .hevc
        default: throw WireError.unknownValue("codec")
        }
        width = Int(try r.u32()); height = Int(try r.u32())
        let n = Int(try r.u8())
        var sets: [Data] = []
        for _ in 0..<n { sets.append(try r.blob()) }
        parameterSets = sets
        displayP3 = r.remaining > 0 ? try r.bool() : false   // absent in older hosts
        sRGBTransfer = r.remaining > 0 ? try r.bool() : false
    }
}

public struct VideoFrame: Equatable, Sendable {
    public var isKeyframe: Bool
    /// Host wall clock (seconds since 1970) when the frame was captured.
    public var captureTime: Double
    /// AVCC/HVCC payload: NAL units with 4-byte big-endian length prefixes.
    public var data: Data

    public init(isKeyframe: Bool, captureTime: Double, data: Data) {
        self.isKeyframe = isKeyframe; self.captureTime = captureTime; self.data = data
    }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: data.count + 9)
        w.bool(isKeyframe)
        w.f64(captureTime)
        w.rest(data)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        isKeyframe = try r.bool()
        captureTime = try r.f64()
        data = r.rest()
    }
}

/// Uncompressed PCM, signed 16-bit little-endian, interleaved. 48 kHz stereo is ~1.5 Mbit/s,
/// small next to the video, and needs no codec delay.
public struct AudioChunk: Equatable, Sendable {
    public var sampleRate: Int
    public var channels: Int
    /// Host wall clock (seconds since 1970) of the first sample.
    public var captureTime: Double
    public var samples: Data

    public init(sampleRate: Int, channels: Int, captureTime: Double, samples: Data) {
        self.sampleRate = sampleRate; self.channels = channels; self.captureTime = captureTime; self.samples = samples
    }

    public var frameCount: Int { channels > 0 ? samples.count / (2 * channels) : 0 }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: samples.count + 14)
        w.u32(UInt32(sampleRate))
        w.u8(UInt8(channels))
        w.f64(captureTime)
        w.rest(samples)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        sampleRate = Int(try r.u32())
        channels = Int(try r.u8())
        guard (1...8).contains(channels), (8000...192_000).contains(sampleRate) else { throw WireError.unknownValue("audio format") }
        captureTime = try r.f64()
        samples = r.rest()
        guard samples.count % (2 * channels) == 0 else { throw WireError.truncated }
    }
}
