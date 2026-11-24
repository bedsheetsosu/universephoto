import Foundation
import IOKit.pwr_mgt
import AppKit
import ServiceManagement
import ScreenCaptureKit
import SwiftUI
import CoreGraphics
import TafelKit
import Combine

enum CaptureMode: String, CaseIterable, Identifiable {
    case display, virtual, region, window
    var id: String { rawValue }
    var title: String {
        switch self {
        case .region: return L("iPad-Ausschnitt")
        case .display: return L("Ganzer Bildschirm")
        case .virtual: return L("Zweiter Bildschirm")
        case .window: return L("Fenster")
        }
    }
    var symbol: String {
        switch self {
        case .region: return "ipad.landscape"
        case .display: return "display"
        case .virtual: return "rectangle.on.rectangle"
        case .window: return "macwindow"
        }
    }
    var help: String {
        switch self {
        case .region: return L("Ausschnitt im iPad-Seitenverhältnis, füllt das iPad ohne schwarze Ränder.")
        case .virtual: return L("Das iPad wird ein zusätzlicher Mac-Bildschirm (wie Sidecar), randlos in iPad-Auflösung. Anordnen unter Systemeinstellungen → Displays. Experimentell: nutzt eine nicht dokumentierte macOS-Schnittstelle (CGVirtualDisplay) und kann mit macOS-Updates aufhören zu funktionieren.")
        case .display: return L("Ganzer Bildschirm; bei abweichendem Seitenverhältnis gibt es Ränder auf dem iPad.")
        case .window: return L("Ein einzelnes Fenster (z. B. Affinity). Position wird alle 0,5 s nachgeführt.")
        }
    }
}

struct DisplayChoice: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let title: String
}

struct WindowChoice: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
}

@MainActor
final class HostController: ObservableObject {
    // Status
    @Published var listenerStatus = L("Startet …")
    /// Titles of the pen-test window in both languages (the window keeps the title it was opened with).
    /// The pen test window's title in every app language (it keeps the title it was opened with).
    /// Listener is up (status texts start with "Bereit"/"Ready", depending on the language at the time).
    @Published var listenerReady = false
    @Published var sessionDevice: String? {
        didSet { updateFlowPause(); if menuIcon.connected != (sessionDevice != nil) { menuIcon.connected = sessionDevice != nil } }
    }
    /// Just what the menu bar icon needs: it must not redraw on every stats tick (each redraw
    /// re-renders the icon in the menu bar of every display, including the iPad's).
    let menuIcon = MenuIconState()
    @Published var sessionLink = ""
    @Published var clientDiagnostics = ""
    /// iPad battery 0…1 and charging state, as reported by the iPad (nil = unknown / not connected).
    // Time-lapse recording
    @Published var timelapseRunning = false {
        didSet { if menuIcon.recording != timelapseRunning { menuIcon.recording = timelapseRunning } }
    }
    @Published var timelapseFrames: Int64 = 0
    @Published var timelapseStarted: Date?
    @Published var timelapseLastFile: URL?
    @Published var timelapseSpeed = UserDefaults.standard.object(forKey: "timelapseSpeed") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(timelapseSpeed, forKey: "timelapseSpeed") }
    }
    private let timelapseSink = TimelapseSink()
    let plugins = PluginManager()

    /// Extra iPads connected as tablets (input only).
    @Published var extraTablets: [String] = []
    /// Display the extra tablets map onto (read from the network queue).
    private let tabletDisplay = LockedDisplayID()

    @Published var ipadBattery: Double? { didSet { checkBattery() } }
    /// The connected iPad's settings profiles and the active one (switchable from the Mac).
    @Published private(set) var ipadProfiles: [ProfileSummary] = []
    @Published private(set) var ipadActiveProfile: String?

    /// Makes `id` the iPad's active profile; the iPad confirms with its next config.
    func activateIPadProfile(_ id: String) {
        guard id != ipadActiveProfile, server.sendSettingsPatch(["activateProfile": id]) else { return }
        ipadActiveProfile = id
    }
    @Published var ipadCharging: Bool? { didSet { checkBattery() } }
    private var batteryWarned = false

    private func checkBattery() {
        let low = (ipadBattery ?? 1) <= 0.15 && ipadCharging != true
        if menuIcon.lowBattery != low { menuIcon.lowBattery = low }
        if low, !batteryWarned {
            batteryWarned = true
            server.sendToast(Toast(text: L("iPad-Akku bei %d %% – bald laden", Int(((ipadBattery ?? 0) * 100).rounded())), seconds: 4))
        } else if !low, (ipadBattery ?? 1) > 0.2 || ipadCharging == true {
            batteryWarned = false
        }
    }
    // MARK: Developer API state
    let devAPI = DeveloperAPI()
    @Published var devAPIClients = 0
    @Published var devAPIError: String?
    @Published var devAPIEnabled = UserDefaults.standard.bool(forKey: "devAPI") {
        didSet {
            guard devAPIEnabled != oldValue else { return }
            UserDefaults.standard.set(devAPIEnabled, forKey: "devAPI")
            applyDevAPI()
        }
    }
    /// Last settings snapshot reported by the iPad.
    private var clientSettingsJSON: [String: Any]?
    private var frontAppInfo: AppInfo?

    @Published var peerToPeer = UserDefaults.standard.bool(forKey: "peerToPeer") {
        didSet {
            guard peerToPeer != oldValue else { return }
            UserDefaults.standard.set(peerToPeer, forKey: "peerToPeer")
            server.peerToPeer = peerToPeer
            server.start()
        }
    }
    @Published var streamDescription = ""
    /// Stream numbers change every second: kept in their own object so only the views that show
    /// them redraw (not the whole window and the menu bar).
    let live = LiveStats()
    var stats: StreamStats {
        get { live.stats }
        set { if live.stats != newValue { live.stats = newValue } }
    }
    @Published var lastError: String?
    @Published var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @Published var accessibilityGranted = InputInjector.isTrusted

    // Pairing
    @Published var pairingCode: String?
    @Published var pairingSecondsLeft = 0
    @Published var lastPaired: String?

    // Source
    /// Default: whole screen. The user's choice is remembered.
    @Published var mode: CaptureMode = HostController.initialMode {
        didSet {
            guard mode != oldValue else { return }
            if mode == .virtual && !Self.secondScreenAvailable { mode = oldValue; return }
            UserDefaults.standard.set(mode.rawValue, forKey: "captureMode")
            updateFollowTimer()
            if oldValue == .virtual { removeVirtualDisplay() }
            restartStream()
            emitDisplay()
        }
    }
    @Published var displays: [DisplayChoice] = []
    @Published var windows: [WindowChoice] = []
    @Published var selectedDisplay: CGDirectDisplayID = CGMainDisplayID() {
        didSet {
            tabletDisplay.value = selectedDisplay
            if selectedDisplay != oldValue { restartStream() }
        }
    }
    @Published var selectedWindow: CGWindowID = 0 { didSet { if selectedWindow != oldValue, mode == .window { restartStream() } } }
    @Published var regionZoom: Double = 1 { didSet { updateRegionLive() } }
    @Published var regionAnchorX: Double = 0.5 { didSet { if !followMoving { updateRegionLive() } } }
    @Published var regionAnchorY: Double = 0.5 { didSet { if !followMoving { updateRegionLive() } } }
    /// "Magnifier follows the pen": in the iPad-section mode the section pans when the pen hovers
    /// near the iPad's edge and jumps to the pointer when it is moved elsewhere (trackpad, mouse).
    @Published var regionFollow = UserDefaults.standard.bool(forKey: "regionFollow") {
        didSet { UserDefaults.standard.set(regionFollow, forKey: "regionFollow"); updateFollowTimer() }
    }
    private var followTimer: Timer?
    /// Laser pointer (set by the iPad's config, read on the network queue) and its overlay.
    private let laserOn = LockedBool()
    private let laser = LaserOverlay()
    @Published var laserColour: LaserOverlay.Colour = .red { didSet { laser.colour = laserColour } }
    private var followMoving = false

    let hostID: String
    let hostName: String
    private(set) var hostKey: Data
    /// One key per paired iPad (see DeviceKeyStore).
    private let keyStore: DeviceKeyStore
    /// Paired iPads for the window's list.
    @Published private(set) var pairedIPads: [DeviceKeyStore.Device] = []
    /// iPads paired before every iPad got its own key may still use the shared key.
    @Published private(set) var legacyPairings = false

    private let server = HostServer()
    private let injector = InputInjector()
    private var streamer: ScreenStreamer?
    private var clientConfig: ClientConfig?
    private var scDisplays: [CGDirectDisplayID: SCDisplay] = [:]
    private var scWindows: [CGWindowID: SCWindow] = [:]
    private var restartTask: Task<Void, Never>?
    private var captureRestarts: [Date] = []
    private var thermalObserver: NSObjectProtocol?

    /// A short system sound when an iPad connects or goes away.
    @Published var connectSound = UserDefaults.standard.bool(forKey: "connectSound") {
        didSet { UserDefaults.standard.set(connectSound, forKey: "connectSound") }
    }

    // MARK: Open at login

    @Published private(set) var openAtLogin = SMAppService.mainApp.status == .enabled

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = L("Beim Anmelden öffnen ging nicht: %@ (liegt die App im Programme-Ordner?)", error.localizedDescription)
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Hot keys

    private let hotkeys = Hotkeys()

    private func hotkey(_ a: Hotkeys.Action) {
        switch a {
        case .tabletMode:
            guard let cfg = clientConfig else { return }
            _ = server.sendSettingsPatch(["settings": ["tabletMode": !(cfg.tabletMode ?? false)]])
        case .palette:
            pickPalette()
        case .windowToIPad:
            moveFrontWindowToIPad()
        }
    }

    /// Puts the front app's window where the iPad looks: the second screen, or the streamed
    /// display/region.
    /// UI checks only (launch argument `-debugOpenMenuPanel YES`): the menu bar panel's content in
    /// an ordinary window, so it can be captured like any window.
    private var debugPanelWindow: NSWindow?

    private func showMenuPanelForChecks() {
        let view = NSHostingView(rootView: HostMenuPanel().environmentObject(self)
            .background(Color.black.opacity(0.3)).background(.ultraThickMaterial).environment(\.colorScheme, .dark))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.contentView = view
        w.title = "Menu panel (check)"
        w.isReleasedWhenClosed = false
        w.center()
        w.orderFront(nil)
        debugPanelWindow = w
    }

    /// The app worked in last other than UniversePen: "front window to the iPad" from our own window
    /// or the menu bar panel means that app's window.
    private var lastOtherApp: pid_t?

    func moveFrontWindowToIPad() {
        guard sessionDevice != nil, mode != .window else { return }
        let area = injector.region
        guard area.width > 50, area.height > 50 else { return }
        let front = NSWorkspace.shared.frontmostApplication.map(\.processIdentifier)
        guard let pid = front != getpid() ? front : lastOtherApp else { return }
        if !Hotkeys.moveFrontWindow(of: pid, into: area) {
            NSLog("Tafel: could not move the front window (Accessibility?)")
        }
    }

    // MARK: Keep awake

    /// While an iPad is connected the Mac's display must not sleep (the capture would stop and the
    /// iPad would show a frozen picture). Connecting also wakes a sleeping display.
    private var awakeAssertion: IOPMAssertionID = 0

    private func updateAwake(sessionActive: Bool) {
        if sessionActive {
            var wake: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("UniversePen: iPad connected" as CFString, kIOPMUserActiveLocal, &wake)
            guard awakeAssertion == 0 else { return }
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "UniversePen: streaming to the iPad" as CFString, &awakeAssertion)
        } else if awakeAssertion != 0 {
            IOPMAssertionRelease(awakeAssertion)
            awakeAssertion = 0
        }
    }

    // MARK: Palette window

    /// Mac area shown as a floating palette on the iPad (global points, top-left origin).
    @Published private(set) var paletteArea: CGRect? = UserDefaults.standard.string(forKey: "paletteArea").map(NSRectFromString) {
        didSet {
            paletteAreaSnapshot.value = paletteArea
            if let a = paletteArea { UserDefaults.standard.set(NSStringFromRect(a), forKey: "paletteArea") }
            else { UserDefaults.standard.removeObject(forKey: "paletteArea") }
        }
    }
    private let paletteAreaSnapshot = LockedRect()
    private let paletteCapture = PaletteCapture()
    private let palettePicker = PalettePicker()

    func pickPalette() {
        palettePicker.run { [weak self] rect in
            guard let self, let rect else { return }
            self.paletteArea = rect
            Task { await self.startPaletteIfPossible() }
        }
    }

    func removePalette() {
        paletteArea = nil
        Task { await stopPalette() }
    }

    private func startPaletteIfPossible() async {
        guard let area = paletteArea, server.hasVideo, clientConfig?.tabletMode != true, clientConfig?.paused != true else { await stopPalette(); return }
        if scDisplays.isEmpty { await refreshSources() }
        let center = CGPoint(x: area.midX, y: area.midY)
        guard let display = scDisplays.values.first(where: { $0.frame.contains(center) }) else { await stopPalette(); return }
        let local = area.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            .intersection(CGRect(origin: .zero, size: display.frame.size))
        guard !local.isEmpty else { return }
        paletteAreaSnapshot.value = local.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
        let server = self.server
        paletteCapture.onJPEG = { server.sendPalette($0) }
        do {
            try await paletteCapture.start(display: display, localRect: local)
        } catch {
            NSLog("Tafel: palette capture failed: %@", error.localizedDescription)
        }
    }

    private func stopPalette() async {
        await paletteCapture.stop()
        server.sendPalette(Data())
    }

    // MARK: Heat guard

    /// Lower frame rate and bitrate while macOS reports the Mac as hot (fanless MacBook Air).
    @Published var heatGuard = UserDefaults.standard.object(forKey: "heatGuard") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(heatGuard, forKey: "heatGuard")
            if heatGuard != oldValue, heatLevel > 0 { restartStream() }
        }
    }
    /// 0 cool, 1 serious, 2 critical (from ProcessInfo.thermalState).
    @Published private(set) var heatLevel = HostController.thermalLevel()

    nonisolated static func thermalLevel() -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .serious: 1
        case .critical: 2
        default: 0
        }
    }

    func effectiveQuality(_ q: StreamQuality) -> StreamQuality {
        heatGuard ? q.cooled(level: heatLevel) : q
    }

    private func observeThermal() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let level = Self.thermalLevel()
                guard level != self.heatLevel else { return }
                NSLog("Tafel: thermal level %d -> %d", self.heatLevel, level)
                self.heatLevel = level
                if self.heatGuard { self.restartStream() }
            }
        }
    }
    private var wakeObservers: [NSObjectProtocol] = []
    /// Whether the private API for "Zweiter Bildschirm" matches what Tafel expects on this macOS.
    static let secondScreenAvailable = VirtualDisplay.availability.isAvailable

    /// Saved mode, falling back to the whole screen if the second screen is unavailable now.
    private static var initialMode: CaptureMode {
        let saved = CaptureMode(rawValue: UserDefaults.standard.string(forKey: "captureMode") ?? "") ?? .display
        return saved == .virtual && !secondScreenAvailable ? .display : saved
    }

    /// The extra display of the "Zweiter Bildschirm" mode (private API, see VirtualDisplay).
    private var virtualDisplay: VirtualDisplay?
    private var virtualTeardown: Task<Void, Never>?
    @Published var virtualDisplayError: String?
    private var pairingTimer: Timer?
    private var windowTracker: Timer?
    private var permissionTimer: Timer?
    private var currentRegionLocal: CGRect = .zero
    /// Thread-safe copy of the stream description for the network queue.
    private let sourceSnapshot = LockedString()

    private static let hostKeyAccount = "host-key"

    /// The running controller, for Shortcuts actions (there is exactly one per app).
    private(set) static weak var current: HostController?

    init() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "hostID") {
            hostID = id
        } else {
            hostID = UUID().uuidString
            defaults.set(hostID, forKey: "hostID")
        }
        hostName = Host.current().localizedName ?? "Mac"
        let upgraded: Bool
        if let k = Keychain.get(account: Self.hostKeyAccount), k.count == 32 {
            hostKey = k
            upgraded = true
        } else {
            hostKey = HostKey.generate()
            Keychain.set(hostKey, account: Self.hostKeyAccount)
            upgraded = false
        }
        keyStore = DeviceKeyStore(legacyKey: hostKey, upgraded: upgraded)
        pairedIPads = keyStore.all
        legacyPairings = keyStore.hasLegacyPairings
        server.keyStore = keyStore
        Self.current = self
        wireServer()
        setupDevAPI()
        observeFrontApp()
        observeWake()
        observeThermal()
        laserColour = laser.colour
        hotkeys.register { [weak self] a in self?.hotkey(a) }
        observeDisplayChanges()
        observeSources()
        updateFollowTimer()
        // Flowing background: only animate while a window is actually visible and no iPad streams.
        for name in [NSApplication.didChangeOcclusionStateNotification, NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFlowPause() }
            }
        }
        setupPlugins()
        let sink = timelapseSink
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            sink.recorder?.stopAndWait()
        }
        server.peerToPeer = peerToPeer
        server.start()
        if UserDefaults.standard.bool(forKey: "debugPairingCodePreview") {
            // UI checks: shows a code without opening the pairing listener (nothing can pair with it).
            pairingCode = PairingCode.generate()
            pairingSecondsLeft = 87
        }
        if UserDefaults.standard.bool(forKey: "debugOpenMenuPanel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showMenuPanelForChecks() }
        }
        Task { await refreshSources() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Only publish real changes: every publish redraws the windows and the menu bar icon.
                guard let self else { return }
                let sr = CGPreflightScreenCaptureAccess(), ax = InputInjector.isTrusted
                if self.screenRecordingGranted != sr { self.screenRecordingGranted = sr }
                if self.accessibilityGranted != ax { self.accessibilityGranted = ax }
            }
        }
    }

    var keyFingerprint: String { HostKey.fingerprint(hostKey) }

    // MARK: Developer API (localhost JSON, see SDK/README.md)

    private func setupDevAPI() {
        devAPI.onClientsChanged = { [weak self] n in self?.devAPIClients = n }
        devAPI.handler = { [weak self] method, params in
            guard let self else { throw DeveloperAPI.APIError("Not ready") }
            return try await self.handleAPI(method, params)
        }
        applyDevAPI()
    }

    private func applyDevAPI() {
        devAPI.stop()
        devAPIError = nil
        guard devAPIEnabled else { return }
        do { try devAPI.start() } catch {
            devAPIError = L("Entwickler-API konnte nicht starten: %@", error.localizedDescription)
        }
    }

    nonisolated static func modeName(_ m: CaptureMode) -> String {
        switch m {
        case .display: return "display"
        case .virtual: return "second-screen"
        case .region: return "region"
        case .window: return "window"
        }
    }

    nonisolated static func penPhaseName(_ p: PenPhase) -> String {
        ["hover", "down", "move", "up", "enter", "exit", "cancel"][Int(p.rawValue)]
    }

    nonisolated static func modifierNames(_ m: ModifierSet) -> [String] {
        var r: [String] = []
        if m.contains(.command) { r.append("cmd") }
        if m.contains(.shift) { r.append("shift") }
        if m.contains(.option) { r.append("option") }
        if m.contains(.control) { r.append("control") }
        return r
    }

    nonisolated static func modifierSet(_ names: [String]) -> ModifierSet {
        var m: ModifierSet = []
        for n in names.map({ $0.lowercased() }) {
            switch n {
            case "cmd", "command", "⌘": m.insert(.command)
            case "shift", "⇧": m.insert(.shift)
            case "option", "alt", "opt", "⌥": m.insert(.option)
            case "control", "ctrl", "⌃": m.insert(.control)
            default: break
            }
        }
        return m
    }

    func statusInfo() -> [String: Any] {
        [
            "connected": sessionDevice != nil,
            "device": sessionDevice ?? NSNull(),
            "link": sessionLink.isEmpty ? NSNull() : sessionLink,
            "usb": sessionLink.hasPrefix("USB"),
            "fps": stats.fps, "mbps": stats.mbps, "targetMbps": stats.targetMbps, "dropped": stats.dropped,
            "ipadBattery": ipadBattery ?? NSNull(), "ipadCharging": ipadCharging ?? NSNull(),
        ]
    }

    func displayInfo() -> [String: Any] {
        var second: [String: Any] = ["available": Self.secondScreenAvailable, "active": virtualDisplay != nil]
        if let v = virtualDisplay {
            second["displayID"] = v.displayID
            second["pixelWidth"] = v.pixelWidth
            second["pixelHeight"] = v.pixelHeight
        }
        var stream: [String: Any] = ["running": streamer != nil, "encoder": streamDescription]
        if let cfg = clientConfig {
            stream["ipadPixelWidth"] = cfg.viewPixelWidth
            stream["ipadPixelHeight"] = cfg.viewPixelHeight
            stream["fps"] = cfg.quality.fps
            stream["codec"] = cfg.quality.codec.rawValue
            stream["bitrateMbps"] = cfg.quality.bitrateMbps
            stream["resolutionScale"] = cfg.quality.resolutionScale
            stream["adaptive"] = cfg.quality.adaptive
            stream["fullSource"] = cfg.quality.fullSource
            stream["audio"] = cfg.quality.audio
        }
        if let s = streamer { stream["width"] = s.outputWidth; stream["height"] = s.outputHeight }
        return ["mode": Self.modeName(mode), "modes": CaptureMode.allCases.map(Self.modeName),
                "secondScreen": second, "stream": stream]
    }

    private func emitDisplay() {
        devAPI.emit("display", event: "display", data: displayInfo())
    }

    private func requireSession() throws {
        guard server.hasSession else { throw DeveloperAPI.APIError("No iPad connected") }
    }

    private func patchIPad(_ patch: [String: Any]) throws -> [String: Any] {
        try requireSession()
        guard server.sendSettingsPatch(patch) else { throw DeveloperAPI.APIError("Could not send to the iPad") }
        return ["sent": true]
    }

    private func buttonJSON(_ b: [String: Any]) throws -> Any {
        let title = b["title"] as? String ?? ""
        let key = (b["key"] as? String) ?? "a"
        let mods = Self.modifierSet(b["modifiers"] as? [String] ?? [])
        var hold: HoldKey?
        if let h = (b["hold"] as? String)?.lowercased() {
            let map: [String: HoldKey] = ["shift": .shift, "option": .option, "alt": .option, "cmd": .command,
                                          "command": .command, "control": .control, "ctrl": .control, "space": .space]
            guard let k = map[h] else { throw DeveloperAPI.APIError("Unknown hold key '\(h)'. Use shift, option, cmd, control, space") }
            hold = k
        }
        let btn = ShortcutButton(title: title.isEmpty ? (hold?.symbol ?? key.uppercased()) : title, shortcut: Shortcut(key, mods), hold: hold)
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(btn))
    }

    /// The iPad's profiles for the developer API and plugins.
    private func profilesInfo() -> [String: Any] {
        ["profiles": ipadProfiles.map { ["id": $0.id, "name": $0.name, "active": $0.id == ipadActiveProfile] },
         "active": ipadActiveProfile ?? NSNull()]
    }

    func handleAPI(_ method: String, _ p: [String: Any]) async throws -> Any {
        switch method {
        // Status / Display API
        case "status.get":
            return statusInfo()
        case "display.get":
            return displayInfo()
        case "display.setMode":
            let map: [String: CaptureMode] = ["display": .display, "second-screen": .virtual, "virtual": .virtual,
                                              "region": .region, "window": .window]
            guard let name = p["mode"] as? String, let m = map[name] else {
                throw DeveloperAPI.APIError("mode must be one of display, second-screen, region, window")
            }
            if m == .virtual && !Self.secondScreenAvailable { throw DeveloperAPI.APIError("Second screen is not available on this macOS") }
            mode = m
            return displayInfo()
        case "display.setQuality":
            var q: [String: Any] = [:]
            for k in ["fps", "bitrateMbps", "resolutionScale", "adaptive", "audio", "codec"] { if let v = p[k] { q[k] = v } }
            guard !q.isEmpty else { throw DeveloperAPI.APIError("Give at least one of fps, bitrateMbps, resolutionScale, adaptive, audio, codec") }
            return try patchIPad(["quality": q])
        case "app.get":
            return frontAppInfo.map { ["bundleID": $0.bundleID, "name": $0.name] } ?? NSNull()

        // Control API
        case "control.shortcut":
            guard let key = p["key"] as? String, !key.isEmpty else { throw DeveloperAPI.APIError("key is required") }
            guard InputInjector.isTrusted else { throw DeveloperAPI.APIError("Accessibility permission missing") }
            injector.shortcut(Shortcut(key, Self.modifierSet(p["modifiers"] as? [String] ?? [])))
            return ["sent": true]
        case "control.text":
            guard let t = p["text"] as? String else { throw DeveloperAPI.APIError("text is required") }
            injector.text(t)
            return ["sent": true]
        case "control.getSettings":
            try requireSession()
            guard let s = clientSettingsJSON else { throw DeveloperAPI.APIError("The iPad has not reported its settings yet") }
            return s
        case "control.patchSettings":
            var patch: [String: Any] = [:]
            if let s = p["settings"] as? [String: Any] { patch["settings"] = s }
            if let q = p["quality"] as? [String: Any] { patch["quality"] = q }
            guard !patch.isEmpty else { throw DeveloperAPI.APIError("Give settings and/or quality objects") }
            return try patchIPad(patch)
        case "control.setPressureCurve":
            var curve: [String: Any] = [:]
            if let pts = p["points"] as? [[Double]] {
                guard pts.count >= 2, pts.allSatisfy({ $0.count == 2 }) else { throw DeveloperAPI.APIError("points: [[x, y], …] with at least 2 points, x and y in 0…1") }
                curve["points"] = pts.sorted { $0[0] < $1[0] }.map { ["x": min(max($0[0], 0), 1), "y": min(max($0[1], 0), 1)] }
            }
            if let g = p["gamma"] as? Double { curve["gamma"] = g; if p["points"] == nil { curve["points"] = [Any]() } }
            if let m = p["minimum"] as? Double { curve["minimum"] = m }
            guard !curve.isEmpty else { throw DeveloperAPI.APIError("Give points, gamma and/or minimum") }
            return try patchIPad(["settings": ["pressure": curve]])
        case "control.setSmoothing":
            var st: [String: Any] = [:]
            if let v = p["stroke"] as? Double { st["positionSmoothing"] = min(max(v, 0), 1) }
            if let v = p["pressure"] as? Double { st["pressureSmoothing"] = min(max(v, 0), 1) }
            guard !st.isEmpty else { throw DeveloperAPI.APIError("Give stroke and/or pressure (0…1)") }
            return try patchIPad(["settings": st])
        case "control.setAppProfile":
            guard let id = p["bundleID"] as? String, let buttons = p["buttons"] as? [[String: Any]] else {
                throw DeveloperAPI.APIError("bundleID and buttons are required")
            }
            let json = try buttons.map(buttonJSON)
            let name = p["name"] as? String ?? id
            return try patchIPad(["settings": ["appShortcutBars": [id: json], "appNames": [id: name]]])
        case "control.removeAppProfile":
            guard let id = p["bundleID"] as? String else { throw DeveloperAPI.APIError("bundleID is required") }
            return try patchIPad(["removeAppProfiles": [id]])
        case "control.setDefaultBar":
            guard let buttons = p["buttons"] as? [[String: Any]] else { throw DeveloperAPI.APIError("buttons is required") }
            return try patchIPad(["settings": ["shortcutBar": try buttons.map(buttonJSON)]])
        case "control.getProfiles":
            try requireSession()
            return profilesInfo()
        case "control.activateProfile":
            try requireSession()
            let id = p["id"] as? String
            let name = p["name"] as? String
            guard let target = ipadProfiles.first(where: { $0.id == id }) ?? ipadProfiles.first(where: { $0.name == name }) else {
                throw DeveloperAPI.APIError("No profile with that id or name; see control.getProfiles")
            }
            activateIPadProfile(target.id)
            return profilesInfo()
        case "api.info":
            return ["api": DeveloperAPI.apiVersion, "app": "UniversePen",
                    "topics": ["input", "gesture", "display", "status", "app"]]
        default:
            throw DeveloperAPI.APIError("Unknown method '\(method)'")
        }
    }

    // MARK: Local control API (URL scheme)

    /// Handles `universepen://…` (also `tafel://…`). Local only: macOS delivers these URLs from
    /// apps on this Mac (Shortcuts, Terminal `open`, Stream Deck …); nothing listens on the network.
    ///   universepen://mode/display | second-screen | region | window
    ///   universepen://pair            open the pairing code
    ///   universepen://pair/stop
    ///   universepen://show            bring the window to the front
    ///   universepen://profile/<name>  switch the connected iPad's profile
    func handle(url: URL) {
        guard ["universepen", "tafel"].contains(url.scheme?.lowercased() ?? "") else { return }
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).map { $0.lowercased() }
        switch parts.first {
        case "mode":
            let map: [String: CaptureMode] = ["display": .display, "second-screen": .virtual, "virtual": .virtual,
                                              "region": .region, "window": .window]
            if let name = parts.dropFirst().first, let m = map[name] { mode = m }
        case "pair":
            if parts.dropFirst().first == "stop" { endPairing() } else if pairingCode == nil { beginPairing() }
            NSApp.activate(ignoringOtherApps: true)
        case "show":
            NSApp.activate(ignoringOtherApps: true)
        case "profile":
            // universepen://profile/<name> (case-insensitive) or the profile's id.
            let raw = url.pathComponents.filter { $0 != "/" }.first ?? ""
            if let p = ipadProfiles.first(where: { $0.id == raw || $0.name.lowercased() == raw.lowercased() }) {
                activateIPadProfile(p.id)
            }
        default:
            NSLog("UniversePen: unknown URL %@", url.absoluteString)
        }
    }

    // MARK: Front app (per-app shortcut bars on the iPad)

    private var frontAppObserver: NSObjectProtocol?

    private func observeFrontApp() {
        let send: (NSRunningApplication?) -> Void = { [weak self] app in
            guard let app, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
            let info = AppInfo(bundleID: id, name: app.localizedName ?? id)
            self?.server.sendAppInfo(info)
            self?.frontAppInfo = info
            self?.lastOtherApp = app.processIdentifier
            self?.devAPI.emit("app", event: "app", data: ["bundleID": info.bundleID, "name": info.name])
            self?.plugins.emit("app", ["bundleID": info.bundleID, "name": info.name])
        }
        send(NSWorkspace.shared.frontmostApplication)
        frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            send(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    // MARK: Server wiring

    private func wireServer() {
        server.hostID = hostID
        server.hostName = hostName
        let injector = self.injector
        let desc = self.sourceSnapshot
        server.sourceDescription = { desc.value }
        // Pen and scroll go straight from the network queue to CGEvent (no main-thread hop).
        let api = devAPI
        let plugins = self.plugins
        let laserOn = self.laserOn
        let laser = self.laser
        server.onPen = { raw in
            // Plugin filters may change, drop or multiply the sample (like OpenTabletDriver filters).
            let samples = plugins.hasFilters ? plugins.filterPen(raw) : [raw]
            for p in samples {
            if laserOn.value {
                // Laser pointer: the pointer follows the Pencil, but nothing is clicked; the
                // marks are drawn by the overlay window.
                let sp = injector.screenPoint(x: p.x, y: p.y)
                var hover = p
                if p.phase != .enter && p.phase != .exit { hover.phase = .hover; hover.pressure = 0 }
                injector.handle(hover)
                let phase = p.phase
                DispatchQueue.main.async { MainActor.assumeIsolated { laser.handle(phase, at: sp) } }
                continue
            }
            injector.handle(p)
            if !plugins.isEmpty { plugins.emit("pen", plugins.penDict(p)) }
            if api.wants("input") {
                let sp = injector.screenPoint(x: p.x, y: p.y)
                api.emit("input", event: "pen", data: [
                    "phase": Self.penPhaseName(p.phase), "x": p.x, "y": p.y, "screenX": sp.x, "screenY": sp.y,
                    "pressure": p.pressure, "tiltX": p.tiltX, "tiltY": p.tiltY, "rotation": p.rotation, "timestamp": p.timestamp,
                ])
            }
            }
        }
        let tabletDisplay = self.tabletDisplay
        server.onExtraPen = { raw in
            let area = CGDisplayBounds(tabletDisplay.value)
            let samples = plugins.hasFilters ? plugins.filterPen(raw) : [raw]
            for p in samples { injector.handle(p, area: area) }
        }
        server.onExtrasChanged = { [weak self] names in Task { @MainActor in self?.extraTablets = names } }
        server.onScroll = { e in
            injector.scroll(e)
            if api.wants("input") {
                api.emit("input", event: "scroll", data: ["x": e.x, "y": e.y, "dx": e.dx, "dy": e.dy, "modifiers": Self.modifierNames(e.modifiers)])
            }
        }
        server.onShortcut = { s in
            DispatchQueue.main.async { injector.shortcut(s) }
            if api.wants("input") { api.emit("input", event: "shortcut", data: ["key": s.key, "modifiers": Self.modifierNames(s.modifiers)]) }
        }
        // Keys stay on the network queue (same queue as pen input, keeps their order).
        server.onKey = { k in
            injector.key(k)
            if api.wants("input") { api.emit("input", event: "key", data: ["hidUsage": k.hidUsage, "down": k.down]) }
        }
        let paletteArea = paletteAreaSnapshot
        server.onPaletteMouse = { m in
            guard let area = paletteArea.value else { return }
            injector.pointer(m, area: area)
        }
        server.onHostCommand = { [weak self] c in
            guard let self else { return }
            switch c {
            case .toggleTimelapse:
                if self.timelapseRunning {
                    self.stopTimelapse()
                    self.server.sendToast(Toast(text: L("Zeitraffer gestoppt – gesichert in Filme → UniversePen"), seconds: 2.4))
                } else {
                    self.startTimelapse()
                    self.server.sendToast(Toast(text: self.timelapseRunning ? L("Zeitraffer läuft am Mac") : L("Zeitraffer konnte nicht starten"), seconds: 2))
                }
            }
        }
        server.onPaletteCommand = { [weak self] c in
            switch c {
            case .pick: self?.pickPalette()
            case .remove: self?.removePalette()
            }
        }
        server.onMouse = { m in
            injector.pointer(m)
            if api.wants("input") {
                let sp = injector.screenPoint(x: m.x, y: m.y)
                let phase = ["move", "down", "up", "exit"][Int(m.phase.rawValue)]
                api.emit("input", event: "touch", data: ["phase": phase, "button": m.button == .left ? "left" : "right",
                                                          "x": m.x, "y": m.y, "screenX": sp.x, "screenY": sp.y])
            }
        }
        server.onGesture = { g in
            api.emit("gesture", event: "gesture", data: ["name": g.name, "value": g.value])
            if !plugins.isEmpty { plugins.emit("gesture", ["name": g.name, "value": g.value]) }
        }
        server.onClientSettings = { [weak self] o in Task { @MainActor in self?.clientSettingsJSON = o } }
        server.onText = { injector.text($0) }
        server.onCharKey = { k in DispatchQueue.main.async { injector.charKey(k.key, down: k.down) } }
        server.onRequestKeyframe = { [weak self] in
            Task { @MainActor in self?.streamer?.requestKeyframe() }
        }
        server.onVideoConnected = { [weak self] in
            Task { @MainActor in
                if self?.streamer == nil { self?.restartStream() } else { self?.streamer?.requestKeyframe() }
            }
        }
        server.onClientConfig = { [weak self, laserOn, laser] cfg in
            let on = cfg.laser ?? false
            if laserOn.value != on {
                laserOn.value = on
                if !on { DispatchQueue.main.async { MainActor.assumeIsolated { laser.clear() } } }
            }
            Task { @MainActor in
                guard let self else { return }
                if let d = cfg.diagnostics, d != self.clientConfig?.diagnostics {
                    self.clientDiagnostics = d
                    NSLog("Tafel iPad-Diagnose: %@", d)
                }
                if self.ipadBattery != cfg.batteryLevel { self.ipadBattery = cfg.batteryLevel }
                let profiles = cfg.profiles ?? []
                if self.ipadProfiles != profiles { self.ipadProfiles = profiles }
                if self.ipadActiveProfile != cfg.activeProfile { self.ipadActiveProfile = cfg.activeProfile }
                if self.ipadCharging != cfg.batteryCharging { self.ipadCharging = cfg.batteryCharging }
                let restart = !cfg.sameStream(as: self.clientConfig)
                self.clientConfig = cfg
                if restart { self.restartStream() }
            }
        }
        server.onSession = { [weak self] name, link in
            if name == nil { injector.releaseAll(); DispatchQueue.main.async { injector.releaseCharKeys() } }
            Task { @MainActor in
                guard let self else { return }
                if self.connectSound, (name != nil) != (self.sessionDevice != nil) {
                    NSSound(named: name != nil ? "Glass" : "Bottle")?.play()
                }
                self.sessionDevice = name
                self.updateAwake(sessionActive: name != nil)
                self.sessionLink = link
                self.plugins.emit(name == nil ? "disconnect" : "connect", ["device": name ?? "", "link": link])
                self.scheduleVirtualTeardown(sessionActive: name != nil)
                if name == nil {
                    self.laserOn.value = false
                    self.laser.clear()
                    self.clientConfig = nil
                    await self.paletteCapture.stop()
                    self.ipadBattery = nil
                    self.ipadCharging = nil
                    self.ipadProfiles = []
                    self.ipadActiveProfile = nil
                    await self.stopStream()
                }
            }
        }
        server.onDevicesChanged = { [weak self] in Task { @MainActor in self?.refreshPairedIPads() } }
        server.onPaired = { [weak self] name in
            Task { @MainActor in
                self?.lastPaired = name
                self?.endPairing()
            }
        }
        server.onStatus = { [weak self] s in Task { @MainActor in self?.listenerStatus = s } }
        server.onReady = { [weak self] r in Task { @MainActor in self?.listenerReady = r } }
    }

    // MARK: Permissions

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        Task { await refreshSources() }
    }

    func requestAccessibility() {
        InputInjector.requestTrust()
    }

    // MARK: Pairing

    func beginPairing() {
        let code = PairingCode.generate()
        pairingCode = code
        pairingSecondsLeft = 120
        // The iPad's own key, accepted by the main listener before the code is even typed.
        let grant = keyStore.preparePairing()
        server.start()
        server.startPairing(code: code, grantKey: grant.key, keyID: grant.id)
        pairingTimer?.invalidate()
        pairingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pairingSecondsLeft -= 1
                if self.pairingSecondsLeft <= 0 { self.endPairing() }
            }
        }
    }

    func endPairing() {
        pairingTimer?.invalidate()
        pairingTimer = nil
        pairingCode = nil
        server.stopPairing()
        // Ended without an iPad: the prepared key must not stay valid.
        if keyStore.cancelPairing() { server.start() }
    }

    /// Generates a new host key: every paired iPad must pair again.
    func unpairAll() {
        hostKey = keyStore.removeAll()
        Keychain.set(hostKey, account: Self.hostKeyAccount)
        server.disconnectSession()
        server.start()
        refreshPairedIPads()
    }

    /// Unpairs one iPad: its key stops working at once and its connection ends.
    func unpair(_ device: DeviceKeyStore.Device) {
        guard let deviceID = keyStore.remove(device.id) else { return }
        server.disconnect(deviceID: deviceID)
        server.start()
        refreshPairedIPads()
    }

    /// Retires the shared key of pairings made before every iPad got its own key.
    func retireLegacyPairings() {
        hostKey = keyStore.retireLegacy()
        Keychain.set(hostKey, account: Self.hostKeyAccount)
        server.start()
        refreshPairedIPads()
    }

    func fingerprint(of device: DeviceKeyStore.Device) -> String { keyStore.fingerprint(of: device.id) ?? "–" }

    private func refreshPairedIPads() {
        let list = keyStore.all
        if pairedIPads != list { pairedIPads = list }
        if legacyPairings != keyStore.hasLegacyPairings { legacyPairings = keyStore.hasLegacyPairings }
    }

    // MARK: Sources

    func refreshSources() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            scDisplays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
            displays = content.displays.map { d in
                let name = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == d.displayID }?.localizedName
                return DisplayChoice(id: d.displayID, title: "\(name ?? "Display \(d.displayID)") (\(Int(d.frame.width))×\(Int(d.frame.height)) pt)")
            }
            let own = Bundle.main.bundleIdentifier
            let candidates = content.windows.filter {
                $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100 && $0.owningApplication?.bundleIdentifier != own
            }
            scWindows = Dictionary(uniqueKeysWithValues: candidates.map { ($0.windowID, $0) })
            windows = candidates.map {
                WindowChoice(id: $0.windowID, title: "\($0.owningApplication?.applicationName ?? "?") – \($0.title ?? L("Fenster"))")
            }
            if scDisplays[selectedDisplay] == nil, let first = content.displays.first { selectedDisplay = first.displayID }
            if selectedWindow == 0 || scWindows[selectedWindow] == nil {
                selectedWindow = candidates.first { $0.owningApplication?.applicationName.localizedCaseInsensitiveContains("affinity") == true }?.windowID
                    ?? candidates.first?.windowID ?? 0
            }
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        } catch {
            lastError = L("Bildschirminhalte nicht verfügbar – Bildschirmaufnahme erlauben? (%@)", error.localizedDescription)
        }
    }

    // MARK: Streaming

    func restartStream() {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            // Debounce rapid config changes (rotation, slider moves).
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.stopStream()
            await self.startStreamIfPossible()
            await self.startPaletteIfPossible()
        }
    }

    /// ScreenCaptureKit ended the capture on its own (display reconfigured, Mac woke up, the
    /// captured window closed …). With an iPad still connected, start it again – a few times,
    /// so a capture that keeps failing ends with a message instead of a loop.
    private func captureStoppedUnexpectedly(_ error: Error?) {
        let now = Date()
        captureRestarts = captureRestarts.filter { now.timeIntervalSince($0) < 30 }
        guard server.hasVideo || sessionDevice != nil, captureRestarts.count < 3 else {
            lastError = L("Aufnahme gestoppt: %@", error?.localizedDescription ?? L("unbekannt"))
            return
        }
        captureRestarts.append(now)
        NSLog("Tafel: capture stopped (%@), restarting", error?.localizedDescription ?? "-")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.restartStream()
        }
    }

    /// After sleep (or the displays sleeping) the old capture is often dead without telling
    /// anyone, and the iPad would keep showing a frozen picture. Start it fresh.
    private func observeWake() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            wakeObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard let self, self.server.hasVideo || self.sessionDevice != nil else { return }
                    NSLog("Tafel: woke up, restarting capture")
                    self.restartStream()
                }
            })
        }
    }

    private func stopStream() async {
        windowTracker?.invalidate()
        windowTracker = nil
        if let s = streamer {
            streamer = nil
            await s.stop()
        }
        stats = StreamStats()
    }

    private func startStreamIfPossible() async {
        guard var cfg = clientConfig, server.hasVideo || sessionDevice != nil else { return }
        cfg.quality = effectiveQuality(cfg.quality)
        // Always refresh: displays and windows may have changed since the last start.
        await refreshSources()
        lastError = nil
        if cfg.tabletMode == true {
            startTabletMode()
            return
        }
        // The iPad is dimmed: nobody looks at the picture, so the Mac does not capture or encode.
        if cfg.paused == true { return }
        let streamer = ScreenStreamer()
        let server = self.server
        let injector = self.injector
        // Drop captured frames while more than ~2 frames are queued on the socket.
        let maxBacklog = max(Int(cfg.quality.bitrateMbps * 1_000_000 / 8 / Double(max(cfg.quality.fps, 1))) * 2, 256 * 1024)
        streamer.shouldEncode = { server.videoBacklog < maxBacklog }
        streamer.onEncoded = { format, frame in server.sendVideo(format: format, frame: frame) }
        streamer.onAudio = { server.sendAudio($0) }
        let sink = timelapseSink
        streamer.onFrame = { sink.append($0, $1) }
        streamer.onStats = { [weak self] s in
            Task { @MainActor in
                guard let self else { return }
                self.stats = s
                if self.devAPI.wants("status") { self.devAPI.emit("status", event: "status", data: self.statusInfo()) }
            }
        }
        streamer.onStopped = { [weak self, weak streamer] e in
            Task { @MainActor in
                guard let self, let streamer, self.streamer === streamer else { return }   // an old stream
                self.streamer = nil
                self.captureStoppedUnexpectedly(e)
            }
        }

        do {
            switch mode {
            case .region, .display, .virtual:
                let chosen: SCDisplay?
                if mode == .virtual {
                    chosen = await ensureVirtualDisplay(width: cfg.viewPixelWidth, height: cfg.viewPixelHeight)
                    if chosen == nil { return }
                } else {
                    chosen = scDisplays[selectedDisplay] ?? scDisplays.values.first
                }
                guard let display = chosen else {
                    lastError = L("Kein Bildschirm gefunden.")
                    return
                }
                let local = CGRect(origin: .zero, size: display.frame.size)
                capturedDisplaySize = display.frame.size
                let rect: CGRect
                if mode == .region {
                    let aspect = Double(cfg.viewPixelWidth) / Double(max(cfg.viewPixelHeight, 1))
                    rect = Geometry.region(aspect: aspect, in: local, zoom: regionZoom,
                                           anchor: CGPoint(x: regionAnchorX, y: regionAnchorY))
                } else {
                    rect = local
                }
                currentRegionLocal = rect
                var size = Geometry.streamSize(sourceAspect: Double(rect.width / rect.height),
                                               targetWidth: cfg.viewPixelWidth, targetHeight: cfg.viewPixelHeight,
                                               scale: cfg.quality.resolutionScale)
                // Full source pixels help when the iPad zooms into a mirrored Mac screen. The second
                // screen is always shown whole, so anything above the iPad's panel ("more space"
                // modes render at up to 1.6× its pixels) is only encoded to be thrown away again:
                // up to 2.5× the encoder and decoder work, heat on the Mac and dropped frames.
                if cfg.quality.fullSource, mode != .virtual,
                   let full = Self.sourcePixelSize(rect, display: display.displayID, codec: cfg.quality.codec),
                   full.width > size.width {
                    size = full
                }
                // Everything on the display is mirrored, our own windows included.
                let filter = SCContentFilter(display: display, excludingWindows: [])
                injector.region = rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
                try await streamer.start(filter: filter, sourceRect: rect, width: size.width, height: size.height, quality: cfg.quality)
            case .window:
                guard let window = scWindows[selectedWindow] else {
                    lastError = L("Kein Fenster gewählt.")
                    return
                }
                let size = Geometry.streamSize(sourceAspect: Double(window.frame.width / window.frame.height),
                                               targetWidth: cfg.viewPixelWidth, targetHeight: cfg.viewPixelHeight,
                                               scale: cfg.quality.resolutionScale)
                injector.region = window.frame
                let filter = SCContentFilter(desktopIndependentWindow: window)
                try await streamer.start(filter: filter, sourceRect: nil, width: size.width, height: size.height, quality: cfg.quality)
                trackWindow(window.windowID)
            }
            self.streamer = streamer
            streamDescription = "\(mode.title) · " + streamer.encoderDescription
            sourceSnapshot.value = streamDescription
            server.sendHostInfo()
            streamer.requestKeyframe()
        } catch {
            lastError = L("Stream konnte nicht starten: %@", error.localizedDescription)
            await streamer.stop()
        }
    }

    /// Backing pixels of `rect` (points) on a display, even, capped to what the encoders and the
    /// iPad's decoder handle (H.264 4096, HEVC 8192 per side).
    static func sourcePixelSize(_ rect: CGRect, display: CGDirectDisplayID, codec: VideoCodec) -> (width: Int, height: Int)? {
        guard let m = CGDisplayCopyDisplayMode(display), m.width > 0 else { return nil }
        let scale = Double(m.pixelWidth) / Double(m.width)
        var w = Double(rect.width) * scale, h = Double(rect.height) * scale
        let cap = codec == .hevc ? 8192.0 : 4096.0
        let f = min(1, cap / max(w, h))
        w *= f; h *= f
        return (max(2, Int(w) & ~1), max(2, Int(h) & ~1))
    }

    // MARK: Plugins

    private func setupPlugins() {
        plugins.injector = injector
        let server = self.server
        plugins.sendToast = { server.sendToast($0) }
        plugins.sendActions = { server.sendPluginActions($0) }
        plugins.apiCall = { [weak self] m, p in
            guard let self else { throw DeveloperAPI.APIError("Not ready") }
            return try await self.handleAPI(m, p)
        }
        server.onRunPluginAction = { [plugins] id in plugins.runAction(id) }
        server.onClipboard = { item in MacClipboard.write(item) }
        server.screenshotProvider = { [weak self] done in
            guard let streamer = self?.streamer else { done(nil); return }
            Task { done(await streamer.screenshot()) }
        }
        server.clipboardProvider = { MacClipboard.read() }
        plugins.startEnabled()
    }

    // MARK: Tablet mode (no picture, the iPad's active area maps onto a whole display)

    var tabletModeActive: Bool { clientConfig?.tabletMode == true }

    private func startTabletMode() {
        // A blank virtual display would only confuse; it comes back when the picture does.
        if virtualDisplay != nil { removeVirtualDisplay() }
        let id = scDisplays[selectedDisplay] != nil ? selectedDisplay : CGMainDisplayID()
        let bounds = CGDisplayBounds(id)
        injector.region = bounds
        capturedDisplaySize = bounds.size
        let name = displays.first { $0.id == id }?.title ?? "Display"
        streamDescription = L("Tablett-Modus") + " · " + name
        sourceSnapshot.value = streamDescription
        server.sendHostInfo()
    }

    // MARK: Time-lapse

    func startTimelapse() {
        guard !timelapseRunning else { return }
        do {
            let r = try TimelapseRecorder(speed: timelapseSpeed)
            r.onProgress = { [weak self] n in self?.timelapseFrames = n }
            r.onStoppedBySize = { [weak self] url in
                guard let self else { return }
                self.timelapseSink.recorder = nil
                self.timelapseRunning = false
                self.timelapseStarted = nil
                if let url { self.timelapseLastFile = url }
                self.lastError = L("Zeitraffer beendet: Die Bildgröße hat sich geändert (andere Quelle oder Auflösung).")
            }
            timelapseFrames = 0
            timelapseStarted = Date()
            timelapseRunning = true
            timelapseSink.recorder = r
        } catch {
            lastError = L("Zeitraffer konnte nicht starten: %@", error.localizedDescription)
        }
    }

    func stopTimelapse() {
        guard let r = timelapseSink.recorder else { timelapseRunning = false; return }
        timelapseSink.recorder = nil
        timelapseRunning = false
        timelapseStarted = nil
        r.stop { [weak self] url in
            guard let self else { return }
            if let url { self.timelapseLastFile = url } else { self.lastError = L("Zeitraffer war leer – nichts gespeichert.") }
        }
    }

    // MARK: Source menu on the iPad

    private var sourceObservers: Set<AnyCancellable> = []

    private func observeSources() {
        Publishers.CombineLatest4($mode, $displays, $windows, $selectedDisplay)
            .combineLatest($selectedWindow)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.publishSourceList() }
            .store(in: &sourceObservers)
        server.onSelectSource = { [weak self] sel in
            Task { @MainActor in await self?.selectSource(sel) }
        }
    }

    private func publishSourceList() {
        let modes = CaptureMode.allCases.map {
            SourceOption(id: Self.modeName($0), title: $0.title, available: $0 != .virtual || Self.secondScreenAvailable)
        }
        server.sendSourceList(SourceList(
            mode: Self.modeName(mode), modes: modes,
            displays: displays.map { d in
                let b = CGDisplayBounds(d.id)
                return SourceOption(id: String(d.id), title: d.title, aspect: b.height > 0 ? Double(b.width / b.height) : nil)
            }, selectedDisplay: String(selectedDisplay),
            windows: windows.map { SourceOption(id: String($0.id), title: $0.title) }, selectedWindow: String(selectedWindow)))
    }

    private func selectSource(_ sel: SourceSelection) async {
        if sel.refresh == true { await refreshSources(); publishSourceList() }
        if let d = sel.display.flatMap({ CGDirectDisplayID($0) }), scDisplays[d] != nil { selectedDisplay = d }
        if let w = sel.window.flatMap({ CGWindowID($0) }), scWindows[w] != nil { selectedWindow = w }
        if let name = sel.mode, let m = CaptureMode.allCases.first(where: { Self.modeName($0) == name }),
           m != .virtual || Self.secondScreenAvailable {
            if m != mode { mode = m } else if sel.window != nil || sel.display != nil { restartStream() }
        }
    }

    // MARK: Display changes

    private var displayChangeWork: DispatchWorkItem?
    /// Size (points) of the display the running stream captures.
    private var capturedDisplaySize: CGSize?

    /// A resolution change ("more space" etc.) changes the captured size in points: restart the
    /// stream so the picture and the Pencil mapping follow (public CGDisplay API).
    private func observeDisplayChanges() {
        let me = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ id, flags, info in
            guard let info, !flags.contains(.beginConfigurationFlag), flags.contains(.setModeFlag) else { return }
            let host = Unmanaged<HostController>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { host.displayModeChanged(id) } }
        }, me)
    }

    private func displayModeChanged(_ id: CGDirectDisplayID) {
        guard streamer != nil || virtualDisplay != nil || tabletModeActive else { return }
        let affected: Bool
        if tabletModeActive { affected = id == selectedDisplay || id == CGMainDisplayID() } else {
        switch mode {
        case .virtual: affected = id == virtualDisplay?.displayID
        case .display, .region: affected = id == selectedDisplay
        case .window: affected = false
        }
        }
        guard affected, CGDisplayBounds(id).size != capturedDisplaySize else { return }
        if mode == .virtual, let s = virtualDisplay?.currentScale { VirtualDisplay.preferredScale = s }
        displayChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.refreshSources()
                self?.restartStream()
            }
        }
        displayChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: Second screen (virtual display, private API)

    /// Creates (or re-creates after rotation) the virtual display and waits until ScreenCaptureKit
    /// lists it.
    private func ensureVirtualDisplay(width: Int, height: Int) async -> SCDisplay? {
        virtualTeardown?.cancel()
        if let v = virtualDisplay, v.pixelWidth != width || v.pixelHeight != height {
            virtualDisplay = nil   // orientation changed
        }
        if virtualDisplay == nil {
            guard let v = VirtualDisplay(pixelWidth: width, pixelHeight: height) else {
                virtualDisplayError = L("Zweiter Bildschirm ist auf diesem macOS nicht verfügbar (private Schnittstelle fehlt oder wurde geändert).")
                lastError = virtualDisplayError
                return nil
            }
            virtualDisplay = v
            virtualDisplayError = nil
            emitDisplay()
        }
        let id = virtualDisplay!.displayID
        for _ in 0..<20 {
            await refreshSources()
            if let d = scDisplays[id] { return d }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        lastError = L("Zweiter Bildschirm wurde angelegt, ist aber für die Aufnahme nicht sichtbar.")
        return nil
    }

    private func removeVirtualDisplay() {
        virtualTeardown?.cancel()
        virtualDisplay = nil
        emitDisplay()
        Task { await refreshSources() }
    }

    /// Without an iPad the extra display would hold windows nobody can see. Keep it through short
    /// drop-outs (USB link resets take ~3 s), remove it after 10 s – macOS then moves the windows back.
    private func scheduleVirtualTeardown(sessionActive: Bool) {
        virtualTeardown?.cancel()
        guard !sessionActive, virtualDisplay != nil else { return }
        virtualTeardown = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, let self, self.sessionDevice == nil else { return }
            self.removeVirtualDisplay()
        }
    }

    private func updateFlowPause() {
        let visible = NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) && !($0 is NSPanel) }
        let pause = sessionDevice != nil || !visible
        if Theme.shared.flowPaused != pause { Theme.shared.flowPaused = pause }
    }

    private func updateFollowTimer() {
        followTimer?.invalidate()
        followTimer = nil
        guard regionFollow, mode == .region else { return }
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followTick() }
        }
    }

    /// One step of "magnifier follows the pen" (30 per second, only in the iPad-section mode).
    private func followTick() {
        guard mode == .region, regionZoom < 0.999, !injector.isPenDown,
              let display = scDisplays[selectedDisplay], let loc = CGEvent(source: nil)?.location else { return }
        let f = display.frame
        let r = currentRegionLocal
        guard f.contains(loc), r.width > 1, r.height > 1 else { return }
        let p = CGPoint(x: loc.x - f.minX, y: loc.y - f.minY)
        var dx: CGFloat = 0, dy: CGFloat = 0
        if !r.insetBy(dx: -2, dy: -2).contains(p) {
            // Pointer moved somewhere else (trackpad, mouse): centre the section on it.
            dx = p.x - r.midX; dy = p.y - r.midY
        } else {
            // Pen near the edge: pan that way, faster the closer it gets (up to ~half a section per second).
            let mx = r.width * 0.12, my = r.height * 0.12, step = 0.5 / 30
            if p.x < r.minX + mx { dx = -r.width * step * (1 - (p.x - r.minX) / mx) }
            else if p.x > r.maxX - mx { dx = r.width * step * (1 - (r.maxX - p.x) / mx) }
            if p.y < r.minY + my { dy = -r.height * step * (1 - (p.y - r.minY) / my) }
            else if p.y > r.maxY - my { dy = r.height * step * (1 - (r.maxY - p.y) / my) }
        }
        guard abs(dx) > 0.01 || abs(dy) > 0.01 else { return }
        let spanX = f.width - r.width, spanY = f.height - r.height
        followMoving = true
        if spanX > 0 { regionAnchorX = min(max((r.minX + dx) / spanX, 0), 1) }
        if spanY > 0 { regionAnchorY = min(max((r.minY + dy) / spanY, 0), 1) }
        followMoving = false
        let before = currentRegionLocal
        updateRegionLive()
        // A hovering pen stays put on the iPad: move the Mac pointer with the section.
        if currentRegionLocal != before {
            let injector = self.injector
            server.queue.async { injector.rehover() }
        }
    }

    private func updateRegionLive() {
        guard mode == .region, let cfg = clientConfig, let streamer,
              let display = scDisplays[selectedDisplay] else { return }
        let local = CGRect(origin: .zero, size: display.frame.size)
        let aspect = Double(cfg.viewPixelWidth) / Double(max(cfg.viewPixelHeight, 1))
        let rect = Geometry.region(aspect: aspect, in: local, zoom: regionZoom, anchor: CGPoint(x: regionAnchorX, y: regionAnchorY))
        guard rect != currentRegionLocal else { return }
        currentRegionLocal = rect
        injector.region = rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
        let w = streamer.outputWidth, h = streamer.outputHeight
        let fps = effectiveQuality(cfg.quality).fps
        Task { await streamer.updateSourceRect(rect, width: w, height: h, fps: fps) }
    }

    /// Keeps Pencil mapping aligned when the captured window moves. Uses the public
    /// CGWindowList API (bounds only, no window contents).
    private func trackWindow(_ id: CGWindowID) {
        windowTracker?.invalidate()
        trackedWindowSize = nil
        pendingWindowSize = nil
        let injector = self.injector
        windowTracker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
                  let b = info.first?[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b) else { return }
            if injector.region != rect { injector.region = rect }
            MainActor.assumeIsolated { self?.windowSizeTick(rect.size) }
        }
    }

    private var trackedWindowSize: CGSize?
    private var pendingWindowSize: CGSize?

    /// The captured window was resized: once its size has held still for one tick, capture it
    /// again at the new shape (the stream keeps its size otherwise and the picture is squeezed).
    private func windowSizeTick(_ size: CGSize) {
        guard let base = trackedWindowSize else { trackedWindowSize = size; return }
        guard abs(size.width - base.width) > 2 || abs(size.height - base.height) > 2 else { pendingWindowSize = nil; return }
        if pendingWindowSize == size {
            trackedWindowSize = size
            pendingWindowSize = nil
            Task { await refreshSources(); restartStream() }
        } else {
            pendingWindowSize = size
        }
    }
}

@MainActor
final class LiveStats: ObservableObject {
    @Published var stats = StreamStats() {
        didSet {
            // The last minute, one sample per update (about one per second), for the sparklines.
            fpsHistory.append(stats.fps); mbpsHistory.append(stats.mbps)
            if fpsHistory.count > 60 { fpsHistory.removeFirst(fpsHistory.count - 60) }
            if mbpsHistory.count > 60 { mbpsHistory.removeFirst(mbpsHistory.count - 60) }
        }
    }
    private(set) var fpsHistory: [Double] = []
    private(set) var mbpsHistory: [Double] = []
}

@MainActor
final class MenuIconState: ObservableObject {
    @Published var connected = false
    /// The connected iPad is below 15 % and not charging.
    @Published var lowBattery = false
    /// A time-lapse is being recorded.
    @Published var recording = false
}

final class LockedRect: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: CGRect?
    var value: CGRect? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = ""
    var value: String {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Display ID readable from the network queue.
final class LockedDisplayID: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: CGDirectDisplayID = CGMainDisplayID()
    var value: CGDirectDisplayID {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
