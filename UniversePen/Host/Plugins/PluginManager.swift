import Foundation
import AppKit
import TafelKit

/// Finds, starts and wires plugins (folders with manifest.json + main.js) in
/// ~/Library/Application Support/UniversePen/Plugins. Plugins are off until switched on.
final class PluginManager: ObservableObject, PluginHost, @unchecked Sendable {
    struct Entry: Identifiable, Equatable {
        let id: String
        var name: String
        var version: String
        var summary: String
        var folder: URL
        var enabled: Bool
        var running: Bool
        var error: String?
    }

    // UI state (main thread)
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var logs: [String: [String]] = [:]
    @Published private(set) var actions: [PluginActionInfo] = []

    let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("UniversePen/Plugins", isDirectory: true)
    }()

    /// Host hooks (set once by HostController).
    var injector: InputInjector?
    var sendToast: ((Toast) -> Void)?
    var sendActions: (([PluginActionInfo]) -> Void)?
    var apiCall: ((String, [String: Any]) async throws -> Any)?

    private let lock = NSLock()
    private var runtimes: [String: PluginRuntime] = [:]
    private var enabledIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "enabledPlugins") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "enabledPlugins") }
    }

    // MARK: Discovery

    func scan() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var found: [Entry] = []
        for d in dirs where (try? d.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let m = Self.manifest(in: d)
            let running = lock.withLock { runtimes[m.id] != nil }
            let old = entries.first { $0.id == m.id }
            found.append(Entry(id: m.id, name: m.name, version: m.version ?? "", summary: m.description ?? "", folder: d,
                               enabled: enabledIDs.contains(m.id), running: running, error: old?.error))
        }
        entries = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func manifest(in dir: URL) -> PluginManifest {
        let fallback = PluginManifest(id: dir.lastPathComponent, name: dir.lastPathComponent, version: nil, description: nil, main: "main.js")
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              var m = try? JSONDecoder().decode(PluginManifest.self, from: data) else { return fallback }
        if m.id.isEmpty { m.id = dir.lastPathComponent }
        return m
    }

    /// Starts every enabled plugin (at launch).
    func startEnabled() {
        scan()
        for e in entries where e.enabled { start(e.id) }
    }

    // MARK: Switching

    func setEnabled(_ id: String, _ on: Bool) {
        var ids = enabledIDs
        if on { ids.insert(id) } else { ids.remove(id) }
        enabledIDs = ids
        if on { start(id) } else { stop(id) }
        scan()
    }

    func reload(_ id: String) {
        stop(id)
        if enabledIDs.contains(id) { start(id) }
        scan()
    }

    private func start(_ id: String) {
        guard let e = entries.first(where: { $0.id == id }) else { return }
        stop(id)
        let rt = PluginRuntime(manifest: Self.manifest(in: e.folder), folder: e.folder, host: self)
        lock.withLock { runtimes[id] = rt }
        log(id, "▶︎ " + L("gestartet"))
        rt.start { [weak self] err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let i = self.entries.firstIndex(where: { $0.id == id }) {
                    self.entries[i].error = err
                    self.entries[i].running = true
                }
            }
        }
    }

    private func stop(_ id: String) {
        let rt = lock.withLock { runtimes.removeValue(forKey: id) }
        guard let rt else { return }
        rt.stop()
        log(id, "■ " + L("gestoppt"))
        pluginActionsChanged()
    }

    // MARK: Files

    func source(of id: String) -> String {
        guard let e = entries.first(where: { $0.id == id }) else { return "" }
        let m = Self.manifest(in: e.folder)
        return (try? String(contentsOf: e.folder.appendingPathComponent(m.main ?? "main.js"), encoding: .utf8)) ?? ""
    }

    func save(_ id: String, source: String) throws {
        guard let e = entries.first(where: { $0.id == id }) else { return }
        let m = Self.manifest(in: e.folder)
        try source.write(to: e.folder.appendingPathComponent(m.main ?? "main.js"), atomically: true, encoding: .utf8)
        reload(id)
    }

    /// New plugin from a small template; returns its id.
    @discardableResult
    func create(named name: String) throws -> String {
        let base = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { s, c in
            if !(c == "-" && s.hasSuffix("-")) { s.append(c) }
        }.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        var id = base.isEmpty ? "plugin" : base
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(id).path) { id = "\(base)-\(n)"; n += 1 }
        let dir = folder.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = PluginManifest(id: id, name: name, version: "1.0", description: "", main: "main.js")
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        try Self.template.write(to: dir.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        scan()
        return id
    }

    /// Copies the bundled example plugins into the plugin folder (existing ones stay untouched).
    func installExamples() -> Int {
        guard let src = Bundle.main.url(forResource: "examples", withExtension: nil) else { return 0 }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var n = 0
        for d in (try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? [] {
            let dest = folder.appendingPathComponent(d.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path), (try? FileManager.default.copyItem(at: d, to: dest)) != nil { n += 1 }
        }
        scan()
        return n
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func clearLog(_ id: String) { logs[id] = [] }

    static let template = """
    // UniversePen plugin – runs on the Mac. Docs: SDK/plugins/README.md
    // Reload after saving (⌘S in the Plugins window does both).

    up.log("hello from my plugin");

    // React to gestures (tap2, swipe3.up, pencil.squeezeBegan, pencil.squeezeEnded, …)
    up.on("gesture", g => {
      if (g.name === "swipe3.up") up.toast("three fingers up");
    });

    // An action you can put on squeeze, the shortcut bar or the radial menu on the iPad.
    up.action({ id: "hello", title: "Hello", icon: "hand.wave" }, () => {
      up.toast("Hello from the Mac!");
    });

    // Change every Pencil point before it reaches the Mac (return null to drop it).
    // up.filter(s => { s.pressure = Math.min(1, s.pressure * 1.2); return s; });

    """

    // MARK: Input path (network queue)

    var hasFilters: Bool { lock.withLock { runtimes.values.contains { $0.hasFilter } } }
    var isEmpty: Bool { lock.withLock { runtimes.isEmpty } }

    /// Runs all plugin filters over a Pencil sample (in plugin name order).
    func filterPen(_ s: PenSample) -> [PenSample] {
        let rts = lock.withLock { runtimes.values.filter { $0.hasFilter }.sorted { $0.manifest.name < $1.manifest.name } }
        var dicts = [penDict(s)]
        for rt in rts {
            guard let out = rt.filter(dicts) else { continue }   // hung: skip it
            dicts = out
        }
        return dicts.compactMap { Self.pen(from: $0, fallback: s) }
    }

    func emit(_ event: String, _ payload: Any) {
        let rts = lock.withLock { Array(runtimes.values) }
        for rt in rts { rt.emit(event, payload) }
    }

    func penDict(_ s: PenSample) -> [String: Any] {
        let sp = injector?.screenPoint(x: s.x, y: s.y) ?? .zero
        return ["phase": HostController.penPhaseName(s.phase), "x": Double(s.x), "y": Double(s.y),
                "screenX": Double(sp.x), "screenY": Double(sp.y),
                "pressure": Double(s.pressure), "tiltX": Double(s.tiltX), "tiltY": Double(s.tiltY),
                "rotation": Double(s.rotation), "time": s.timestamp * 1000]
    }

    static func pen(from d: [String: Any], fallback: PenSample) -> PenSample? {
        func f(_ k: String, _ v: Float) -> Float { (d[k] as? NSNumber).map { $0.floatValue } ?? v }
        let names = ["hover", "down", "move", "up", "enter", "exit", "cancel"]
        let phase = (d["phase"] as? String).flatMap { names.firstIndex(of: $0) }.flatMap { PenPhase(rawValue: UInt8($0)) } ?? fallback.phase
        return PenSample(phase: phase, x: min(max(f("x", fallback.x), 0), 1), y: min(max(f("y", fallback.y), 0), 1),
                         pressure: min(max(f("pressure", fallback.pressure), 0), 1),
                         tiltX: f("tiltX", fallback.tiltX), tiltY: f("tiltY", fallback.tiltY), rotation: f("rotation", fallback.rotation),
                         timestamp: (d["time"] as? NSNumber).map { $0.doubleValue / 1000 } ?? fallback.timestamp)
    }

    func runAction(_ fullID: String) {
        let parts = fullID.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let rt = lock.withLock({ runtimes[parts[0]] }) else { return }
        rt.runAction(parts[1])
    }

    // MARK: PluginHost

    func pluginShortcut(_ key: String, _ modifiers: [String]) {
        let s = Shortcut(key, HostController.modifierSet(modifiers))
        DispatchQueue.main.async { [injector] in injector?.shortcut(s) }
    }

    func pluginText(_ text: String) { injector?.text(text) }

    func pluginScroll(dx: Double, dy: Double) { injector?.scrollPixels(dx: dx, dy: dy) }

    func pluginToast(_ text: String, seconds: Double) { sendToast?(Toast(text: text, seconds: min(max(seconds, 0.3), 10))) }

    func pluginCall(_ method: String, _ params: [String: Any]) -> (Any?, String?) {
        guard let apiCall else { return (nil, "not ready") }
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Any?
        nonisolated(unsafe) var failure: String?
        nonisolated(unsafe) let p = params
        Task { @MainActor in
            do { result = try await apiCall(method, p) } catch { failure = error.localizedDescription }
            sem.signal()
        }
        if sem.wait(timeout: .now() + 3) == .timedOut { return (nil, "timeout") }
        return (result, failure)
    }

    func pluginLog(_ plugin: String, _ line: String) { log(plugin, line) }

    func pluginActionsChanged() {
        let list = lock.withLock { runtimes.values.flatMap { $0.actions } }.sorted { $0.title < $1.title }
        sendActions?(list)
        DispatchQueue.main.async { self.actions = list }
    }

    private func log(_ id: String, _ line: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let stamped = "\(f.string(from: Date()))  \(line)"
        DispatchQueue.main.async {
            var l = self.logs[id] ?? []
            l.append(stamped)
            if l.count > 300 { l.removeFirst(l.count - 300) }
            self.logs[id] = l
        }
    }
}
