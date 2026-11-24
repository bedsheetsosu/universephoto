// UniversePenKit – MIT License, Copyright (c) 2026 Biene. See SDK/LICENSE.
//
// Swift client for the UniversePen developer API (localhost, newline-delimited JSON).
// The API must be switched on in the UniversePen Mac app ("Entwickler-API" / Developer API).

import Foundation
import Network

public enum UniversePenError: Error, LocalizedError {
    case notConnected
    case server(String)
    case badResponse
    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to UniversePen (is the Developer API switched on?)"
        case .server(let m): return m
        case .badResponse: return "Unexpected response"
        }
    }
}

/// One event from UniversePen. `name` is e.g. "pen", "touch", "scroll", "key", "shortcut",
/// "gesture", "status", "display", "app"; `data` is the JSON object documented in SDK/README.md.
public struct UniversePenEvent: @unchecked Sendable {
    public let name: String
    public let data: [String: Any]
}

/// A pen sample (Input API).
public struct PenSample: Sendable {
    public let phase: String          // hover, down, move, up, enter, exit, cancel
    public let x: Double, y: Double   // 0…1 over the streamed image
    public let screenX: Double, screenY: Double  // Mac screen points, top-left origin
    public let pressure: Double, tiltX: Double, tiltY: Double, rotation: Double
    public let timestamp: Double

    init?(_ d: [String: Any]) {
        func n(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
        guard let p = d["phase"] as? String else { return nil }
        phase = p; x = n("x"); y = n("y"); screenX = n("screenX"); screenY = n("screenY")
        pressure = n("pressure"); tiltX = n("tiltX"); tiltY = n("tiltY"); rotation = n("rotation"); timestamp = n("timestamp")
    }
}

public final class UniversePen: @unchecked Sendable {
    public static let defaultPort: UInt16 = 47800

    private let queue = DispatchQueue(label: "UniversePenKit")
    private var conn: NWConnection?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Any, Error>] = [:]
    private var eventContinuations: [UUID: AsyncStream<UniversePenEvent>.Continuation] = [:]

    public init() {}

    /// Connects to UniversePen on this Mac.
    public func connect(port: UInt16 = UniversePen.defaultPort) async throws {
        let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        conn = c
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            c.stateUpdateHandler = { st in
                switch st {
                case .ready: if !resumed { resumed = true; cont.resume() }
                case .failed(let e), .waiting(let e): if !resumed { resumed = true; c.cancel(); cont.resume(throwing: e) }
                default: break
                }
            }
            c.start(queue: queue)
        }
        receive()
    }

    public func disconnect() { conn?.cancel(); conn = nil }

    /// Calls a raw API method (see SDK/README.md for all methods).
    @discardableResult
    public func call(_ method: String, _ params: [String: Any] = [:]) async throws -> Any {
        guard let conn else { throw UniversePenError.notConnected }
        return try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                let id = nextID; nextID += 1
                pending[id] = cont
                var line = (try? JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])) ?? Data()
                line.append(0x0A)
                conn.send(content: line, completion: .contentProcessed { _ in })
            }
        }
    }

    /// All events (after `subscribe`). Each call returns an independent stream.
    public func events() -> AsyncStream<UniversePenEvent> {
        AsyncStream { cont in
            let id = UUID()
            queue.async { self.eventContinuations[id] = cont }
            cont.onTermination = { _ in self.queue.async { self.eventContinuations[id] = nil } }
        }
    }

    // MARK: Input API

    /// Starts the "input" and "gesture" event topics.
    public func subscribeInput() async throws { try await call("subscribe", ["topics": ["input", "gesture"]]) }

    /// Pen samples only (pressure, tilt, rotation, hover).
    public func penSamples() -> AsyncCompactMapSequence<AsyncStream<UniversePenEvent>, PenSample> {
        events().compactMap { $0.name == "pen" ? PenSample($0.data) : nil }
    }

    // MARK: Display API

    public enum Mode: String { case display, secondScreen = "second-screen", region, window }

    public func display() async throws -> [String: Any] { try await call("display.get") as? [String: Any] ?? [:] }
    public func status() async throws -> [String: Any] { try await call("status.get") as? [String: Any] ?? [:] }
    public func setMode(_ m: Mode) async throws { try await call("display.setMode", ["mode": m.rawValue]) }
    /// Any of: fps, bitrateMbps, resolutionScale, adaptive, audio, codec ("h264"/"hevc").
    public func setQuality(_ q: [String: Any]) async throws { try await call("display.setQuality", q) }

    // MARK: Control API

    public func shortcut(_ key: String, modifiers: [String] = []) async throws {
        try await call("control.shortcut", ["key": key, "modifiers": modifiers])
    }
    /// Control points (x = Pencil force, y = output pressure, both 0…1), monotone-interpolated.
    public func setPressureCurve(_ points: [(Double, Double)]) async throws {
        try await call("control.setPressureCurve", ["points": points.map { [$0.0, $0.1] }])
    }
    public func setSmoothing(stroke: Double? = nil, pressure: Double? = nil) async throws {
        var p: [String: Any] = [:]
        if let stroke { p["stroke"] = stroke }
        if let pressure { p["pressure"] = pressure }
        try await call("control.setSmoothing", p)
    }
    /// Buttons: ["title": "Undo", "key": "z", "modifiers": ["cmd"]] or ["title": "⇧", "hold": "shift"].
    public func setAppProfile(bundleID: String, name: String? = nil, buttons: [[String: Any]]) async throws {
        var p: [String: Any] = ["bundleID": bundleID, "buttons": buttons]
        if let name { p["name"] = name }
        try await call("control.setAppProfile", p)
    }
    public func settings() async throws -> [String: Any] { try await call("control.getSettings") as? [String: Any] ?? [:] }
    public func patchSettings(settings: [String: Any]? = nil, quality: [String: Any]? = nil) async throws {
        var p: [String: Any] = [:]
        if let settings { p["settings"] = settings }
        if let quality { p["quality"] = quality }
        try await call("control.patchSettings", p)
    }

    // MARK: Plumbing

    private func receive() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data {
                self.buffer.append(data)
                while let nl = self.buffer.firstIndex(of: 0x0A) {
                    let line = self.buffer[self.buffer.startIndex..<nl]
                    self.buffer.removeSubrange(self.buffer.startIndex...nl)
                    self.handle(Data(line))
                }
            }
            if done || err != nil {
                for c in self.pending.values { c.resume(throwing: UniversePenError.notConnected) }
                self.pending.removeAll()
                for c in self.eventContinuations.values { c.finish() }
                return
            }
            self.receive()
        }
    }

    private func handle(_ line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let name = obj["event"] as? String {
            let ev = UniversePenEvent(name: name, data: obj["data"] as? [String: Any] ?? [:])
            for c in eventContinuations.values { c.yield(ev) }
        } else if let id = (obj["id"] as? NSNumber)?.intValue, let cont = pending.removeValue(forKey: id) {
            if let e = obj["error"] as? String { cont.resume(throwing: UniversePenError.server(e)) } else { cont.resume(returning: obj["result"] ?? NSNull()) }
        }
    }
}
