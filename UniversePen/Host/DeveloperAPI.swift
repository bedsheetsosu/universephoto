import Foundation
import Network

/// UniversePen developer API: newline-delimited JSON over TCP on 127.0.0.1 only.
/// Off by default; enabled in the Mac app. Documented in SDK/README.md (MIT).
///
/// Request:  {"id": 1, "method": "display.get", "params": {…}}
/// Response: {"id": 1, "result": …}  or  {"id": 1, "error": "…"}
/// Event:    {"event": "pen", "data": {…}}   (after "subscribe")
final class DeveloperAPI {
    static let defaultPort: UInt16 = 47800
    static let apiVersion = 1

    /// Handles a method call on the main actor; returns a JSON-serialisable result or throws.
    var handler: ((_ method: String, _ params: [String: Any]) async throws -> Any)?
    var onClientsChanged: ((Int) -> Void)?

    private let queue = DispatchQueue(label: "universepen.devapi")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]

    private final class Client {
        let conn: NWConnection
        var buffer = Data()
        var topics: Set<String> = []
        init(_ c: NWConnection) { conn = c }
    }

    struct APIError: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }

    func start(port: UInt16 = DeveloperAPI.defaultPort) throws {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel(); listener = nil
            for c in clients.values { c.conn.cancel() }
            clients.removeAll()
            notifyCount()
        }
    }

    /// True if at least one client listens to `topic` (cheap check before building events).
    func wants(_ topic: String) -> Bool { queue.sync { clients.values.contains { $0.topics.contains(topic) } } }

    /// Sends an event to every client subscribed to `topic`. Thread-safe.
    func emit(_ topic: String, event: String, data: Any) {
        queue.async { [self] in
            let targets = clients.values.filter { $0.topics.contains(topic) }
            guard !targets.isEmpty, let line = Self.line(["event": event, "data": data]) else { return }
            for c in targets { c.conn.send(content: line, completion: .contentProcessed { _ in }) }
        }
    }

    // MARK: Connections

    private func accept(_ c: NWConnection) {
        let client = Client(c)
        let id = ObjectIdentifier(client)
        clients[id] = client
        notifyCount()
        c.stateUpdateHandler = { [weak self] st in
            switch st {
            case .failed, .cancelled:
                self?.clients[id] = nil
                self?.notifyCount()
            default: break
            }
        }
        c.start(queue: queue)
        // Greeting with the API version, so clients can check compatibility.
        if let hello = Self.line(["event": "hello", "data": ["api": Self.apiVersion, "app": "UniversePen"]]) {
            c.send(content: hello, completion: .contentProcessed { _ in })
        }
        receive(client)
    }

    private func receive(_ client: Client) {
        client.conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data {
                client.buffer.append(data)
                while let nl = client.buffer.firstIndex(of: 0x0A) {
                    let lineData = client.buffer[client.buffer.startIndex..<nl]
                    client.buffer.removeSubrange(client.buffer.startIndex...nl)
                    self.handleLine(Data(lineData), from: client)
                }
                if client.buffer.count > 1_000_000 { client.conn.cancel(); return }   // runaway line
            }
            if done || err != nil { client.conn.cancel(); return }
            self.receive(client)
        }
    }

    private func handleLine(_ data: Data, from client: Client) {
        guard !data.isEmpty else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = obj["method"] as? String else {
            reply(client, id: nil, error: "Invalid request: expected {\"id\", \"method\", \"params\"}")
            return
        }
        let id = obj["id"]
        let params = obj["params"] as? [String: Any] ?? [:]

        switch method {
        case "subscribe", "unsubscribe":
            let topics = (params["topics"] as? [String]) ?? []
            let valid: Set<String> = ["input", "gesture", "display", "status", "app"]
            let bad = topics.filter { !valid.contains($0) }
            guard bad.isEmpty else { reply(client, id: id, error: "Unknown topics: \(bad). Valid: \(valid.sorted())"); return }
            if method == "subscribe" { client.topics.formUnion(topics) } else { client.topics.subtract(topics) }
            reply(client, id: id, result: ["topics": client.topics.sorted()])
        default:
            guard let handler else { reply(client, id: id, error: "Not ready"); return }
            Task { @MainActor in
                do {
                    let r = try await handler(method, params)
                    self.queue.async { self.reply(client, id: id, result: r) }
                } catch {
                    self.queue.async { self.reply(client, id: id, error: error.localizedDescription) }
                }
            }
        }
    }

    private func reply(_ client: Client, id: Any?, result: Any? = nil, error: String? = nil) {
        var msg: [String: Any] = ["id": id ?? NSNull()]
        if let error { msg["error"] = error } else { msg["result"] = result ?? NSNull() }
        if let line = Self.line(msg) { client.conn.send(content: line, completion: .contentProcessed { _ in }) }
    }

    private func notifyCount() {
        let n = clients.count
        DispatchQueue.main.async { self.onClientsChanged?(n) }
    }

    private static func line(_ obj: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(obj),
              var d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return nil }
        d.append(0x0A)
        return d
    }
}
