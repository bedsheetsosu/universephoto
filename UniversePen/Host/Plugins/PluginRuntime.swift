import Foundation
import JavaScriptCore
import TafelKit

/// What a plugin may do on the host. Implemented by `PluginManager`; called on the plugin's queue.
protocol PluginHost: AnyObject, Sendable {
    func pluginShortcut(_ key: String, _ modifiers: [String])
    func pluginText(_ text: String)
    func pluginScroll(dx: Double, dy: Double)
    func pluginToast(_ text: String, seconds: Double)
    /// Synchronous developer-API call (main actor), nil result = error in `error`.
    func pluginCall(_ method: String, _ params: [String: Any]) -> (Any?, String?)
    func pluginLog(_ plugin: String, _ line: String)
    func pluginActionsChanged()
}

struct PluginManifest: Codable, Equatable {
    var id: String
    var name: String
    var version: String?
    var description: String?
    var main: String?
}

/// One plugin: its own JavaScriptCore context on its own serial queue (public JavaScriptCore API).
///
/// A plugin that hangs only blocks its own queue: filters that do not answer within
/// `filterTimeout` mark it as hung, and the Pencil keeps working unfiltered.
final class PluginRuntime: @unchecked Sendable {
    static let filterTimeout: DispatchTimeInterval = .milliseconds(20)

    let manifest: PluginManifest
    let folder: URL
    private weak var host: PluginHost?
    private let queue: DispatchQueue
    private var ctx: JSContext?
    private var handlers: [String: [JSValue]] = [:]
    private var filters: [JSValue] = []
    private var actionFns: [String: JSValue] = [:]
    private var timers: [Int: DispatchSourceTimer] = [:]
    private var nextTimer = 1
    private var inFilter = false

    private let lock = NSLock()
    private var _hasFilter = false
    private var _hung = false
    private var _actions: [PluginActionInfo] = []
    var hasFilter: Bool { lock.withLock { _hasFilter && !_hung } }
    var hung: Bool { lock.withLock { _hung } }
    var actions: [PluginActionInfo] { lock.withLock { _actions } }

    init(manifest: PluginManifest, folder: URL, host: PluginHost) {
        self.manifest = manifest
        self.folder = folder
        self.host = host
        queue = DispatchQueue(label: "universepen.plugin.\(manifest.id)", qos: .userInteractive)
    }

    // MARK: Lifecycle

    /// Loads and runs main.js. Calls back with an error text (nil = running).
    func start(_ done: @escaping (String?) -> Void) {
        queue.async { [self] in
            let file = folder.appendingPathComponent(manifest.main ?? "main.js")
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                done(String(format: L("%@ nicht gefunden"), file.lastPathComponent)); return
            }
            guard let ctx = JSContext() else { done("JavaScriptCore"); return }
            ctx.name = manifest.name
            var firstError: String?
            ctx.exceptionHandler = { [weak self] _, ex in
                let line = ex?.objectForKeyedSubscript("line")?.toString() ?? "?"
                let msg = "\(ex?.toString() ?? "error") (line \(line))"
                if firstError == nil { firstError = msg }
                self?.log("⚠︎ " + msg)
            }
            self.ctx = ctx
            installAPI(ctx)
            ctx.evaluateScript(Self.prelude, withSourceURL: URL(string: "universepen://prelude.js"))
            ctx.evaluateScript(source, withSourceURL: file)
            publishActions()
            done(firstError)
        }
    }

    func stop() {
        queue.async { [self] in
            for t in timers.values { t.cancel() }
            timers.removeAll()
            handlers.removeAll()
            filters.removeAll()
            actionFns.removeAll()
            ctx = nil
            lock.withLock { _hasFilter = false; _actions = [] }
        }
    }

    // MARK: Calls from the host

    func emit(_ event: String, _ payload: Any) {
        queue.async { [self] in
            guard let ctx, let fns = handlers[event], !fns.isEmpty else { return }
            let arg = JSValue(object: payload, in: ctx) as Any
            for f in fns { f.call(withArguments: [arg]) }
        }
    }

    /// Runs the pen filters on `samples` (dictionaries). nil = timed out (plugin marked hung).
    func filter(_ samples: [[String: Any]]) -> [[String: Any]]? {
        var out: [[String: Any]] = samples
        let sem = DispatchSemaphore(value: 0)
        queue.async { [self] in
            defer { sem.signal() }
            guard let ctx, !filters.isEmpty else { return }
            inFilter = true
            defer { inFilter = false }
            var current = samples
            for f in filters {
                var next: [[String: Any]] = []
                for s in current {
                    guard let r = f.call(withArguments: [JSValue(object: s, in: ctx) as Any]) else { next.append(s); continue }
                    if r.isNull || r.isUndefined { continue }
                    if r.isArray { next += (r.toArray() ?? []).compactMap { $0 as? [String: Any] } }
                    else if let d = r.toDictionary() as? [String: Any] { next.append(d) }
                }
                current = next
            }
            out = current
        }
        if sem.wait(timeout: .now() + Self.filterTimeout) == .timedOut {
            lock.withLock { _hung = true }
            log("⚠︎ " + L("Filter zu langsam (über 20 ms) – Plugin angehalten. Neu laden, um es wieder zu starten."))
            return nil
        }
        return out
    }

    func runAction(_ actionID: String) {
        queue.async { [self] in
            guard let f = actionFns[actionID] else { return }
            f.call(withArguments: [])
        }
    }

    // MARK: API

    private func log(_ s: String) { host?.pluginLog(manifest.id, s) }

    private func publishActions() {
        let list = actionFns.keys.sorted().compactMap { id -> PluginActionInfo? in
            guard let f = actionFns[id] else { return nil }
            let title = f.objectForKeyedSubscript("__title")?.toString() ?? id
            let icon = f.objectForKeyedSubscript("__icon")?.toString()
            return PluginActionInfo(id: "\(manifest.id)/\(id)", title: title, icon: (icon?.isEmpty ?? true) || icon == "undefined" ? nil : icon,
                                    plugin: manifest.name)
        }
        lock.withLock { _actions = list }
        host?.pluginActionsChanged()
    }

    private func installAPI(_ ctx: JSContext) {
        func set(_ name: String, _ block: Any) { ctx.setObject(block, forKeyedSubscript: name as NSString) }

        let on: @convention(block) (String, JSValue) -> Void = { [weak self] name, fn in
            self?.handlers[name, default: []].append(fn)
        }
        let filter: @convention(block) (JSValue) -> Void = { [weak self] fn in
            guard let self else { return }
            filters.append(fn)
            lock.withLock { self._hasFilter = true }
        }
        let action: @convention(block) (String, String, String, JSValue) -> Void = { [weak self] id, title, icon, fn in
            guard let self else { return }
            fn.setObject(title, forKeyedSubscript: "__title" as NSString)
            fn.setObject(icon, forKeyedSubscript: "__icon" as NSString)
            actionFns[id] = fn
            publishActions()
        }
        let shortcut: @convention(block) (String, [String]) -> Void = { [weak self] k, m in self?.host?.pluginShortcut(k, m) }
        let text: @convention(block) (String) -> Void = { [weak self] t in self?.host?.pluginText(t) }
        let scroll: @convention(block) (Double, Double) -> Void = { [weak self] dx, dy in self?.host?.pluginScroll(dx: dx, dy: dy) }
        let toast: @convention(block) (String, Double) -> Void = { [weak self] t, s in self?.host?.pluginToast(t, seconds: s) }
        let call: @convention(block) (String, JSValue) -> Any = { [weak self] method, params in
            guard let self, let host else { return ["__error": "not ready"] }
            if inFilter { return ["__error": "up.call is not allowed inside up.filter (it would block the Pencil)"] }
            let (r, err) = host.pluginCall(method, (params.toDictionary() as? [String: Any]) ?? [:])
            if let err { return ["__error": err] }
            return r ?? NSNull()
        }
        let logFn: @convention(block) (String) -> Void = { [weak self] s in self?.log(s) }
        let storageKey = "pluginStorage.\(manifest.id)"
        let storageGet: @convention(block) (String) -> Any = { k in
            (UserDefaults.standard.dictionary(forKey: storageKey)?[k]) ?? NSNull()
        }
        let storageSet: @convention(block) (String, JSValue) -> Void = { k, v in
            var d = UserDefaults.standard.dictionary(forKey: storageKey) ?? [:]
            if v.isNull || v.isUndefined { d[k] = nil } else if let o = v.toObject(), JSONSerialization.isValidJSONObject([o]) { d[k] = o }
            UserDefaults.standard.set(d, forKey: storageKey)
        }
        let setTimer: @convention(block) (JSValue, Double, Bool) -> Int = { [weak self] fn, ms, rep in
            guard let self else { return 0 }
            let id = nextTimer; nextTimer += 1
            let t = DispatchSource.makeTimerSource(queue: queue)
            let interval = max(ms, rep ? 10 : 0) / 1000
            t.schedule(deadline: .now() + interval, repeating: rep ? interval : .infinity)
            t.setEventHandler { [weak self] in
                fn.call(withArguments: [])
                if !rep { self?.timers[id]?.cancel(); self?.timers[id] = nil }
            }
            timers[id] = t
            t.resume()
            return id
        }
        let clearTimer: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timers[id]?.cancel(); self?.timers[id] = nil
        }
        let now: @convention(block) () -> Double = { ProcessInfo.processInfo.systemUptime * 1000 }

        set("__on", on); set("__filter", filter); set("__action", action)
        set("__shortcut", shortcut); set("__text", text); set("__scroll", scroll); set("__toast", toast)
        set("__call", call); set("__log", logFn); set("__storageGet", storageGet); set("__storageSet", storageSet)
        set("__setTimer", setTimer); set("__clearTimer", clearTimer); set("__now", now)
    }

    /// The `up` object plugins see (documented in SDK/plugins/README.md).
    static let prelude = #"""
    const up = {
      on: (name, fn) => __on(String(name), fn),
      filter: (fn) => __filter(fn),
      action: (o, fn) => __action(String(o.id), String(o.title || o.id), o.icon ? String(o.icon) : "", fn),
      shortcut: (key, mods) => __shortcut(String(key), (mods || []).map(String)),
      text: (s) => __text(String(s)),
      scroll: (dx, dy) => __scroll(+dx || 0, +dy || 0),
      toast: (text, seconds) => __toast(String(text), +seconds || 2),
      call: (method, params) => {
        const r = __call(String(method), params || {});
        if (r && r.__error) throw new Error(r.__error);
        return r;
      },
      log: (...a) => __log(a.map(x => typeof x === "string" ? x : JSON.stringify(x)).join(" ")),
      now: () => __now(),
      storage: { get: (k) => __storageGet(String(k)), set: (k, v) => __storageSet(String(k), v) },
      settings: { get: () => up.call("control.getSettings"), patch: (s) => up.call("control.patchSettings", { settings: s }) },
      display: { get: () => up.call("display.get"), setMode: (m) => up.call("display.setMode", { mode: m }) },
      frontApp: () => up.call("app.get"),
      status: () => up.call("status.get"),
      profiles: {
        get: () => up.call("control.getProfiles"),
        activate: (idOrName) => up.call("control.activateProfile", { id: String(idOrName), name: String(idOrName) }),
      },
    };
    const console = { log: up.log, info: up.log, warn: up.log, error: up.log };
    function setTimeout(fn, ms) { return __setTimer(fn, +ms || 0, false); }
    function setInterval(fn, ms) { return __setTimer(fn, +ms || 0, true); }
    function clearTimeout(id) { __clearTimer(id); }
    function clearInterval(id) { __clearTimer(id); }
    """#
}
