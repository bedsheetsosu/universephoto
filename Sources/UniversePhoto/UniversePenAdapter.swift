import Foundation
import Combine
import Network

/// Developer API v1 sample. Coordinates in `screenX/Y` are global Mac points,
/// measured from the top-left of the main display, as specified by UniversePen.
struct PenSample: Codable, Equatable, Sendable {
    var phase: String
    var x: Double
    var y: Double
    var screenX: Double?
    var screenY: Double?
    var pressure: Double
    var tiltX: Double?
    var tiltY: Double?
    var rotation: Double?
    var timestamp: Double?

    func validated() throws -> PenSample {
        let phases = ["hover", "down", "move", "up", "enter", "exit", "cancel"]
        guard phases.contains(phase), x.isFinite, y.isFinite, pressure.isFinite,
              [screenX, screenY, tiltX, tiltY, rotation, timestamp].allSatisfy({ $0?.isFinite ?? true }) else {
            throw PenProtocolError.invalidSample
        }
        var sample = self
        sample.x = min(1, max(0, x)); sample.y = min(1, max(0, y))
        sample.pressure = min(1, max(0, pressure))
        return sample
    }
}

enum PenProtocolError: Error, LocalizedError, Equatable, Sendable {
    case oversizedLine, invalidSample, unsupportedAPI(Int), server(String)
    // Errors remain language-neutral while carried by the network queue.
    var errorDescription: String? {
        switch self {
        case .oversizedLine: "UniversePen: message exceeds the size limit."
        case .invalidSample: "UniversePen: invalid pen sample."
        case .unsupportedAPI(let version): "UniversePen: API version \(version) is not supported."
        case .server: "UniversePen rejected the request."
        }
    }
    @MainActor var localizedMessage: String {
        switch self {
        case .oversizedLine: L("UniversePen: message exceeds the size limit.")
        case .invalidSample: L("UniversePen: invalid pen sample.")
        case .unsupportedAPI(let version): LF("UniversePen: API version %d is not supported.", version)
        case .server: L("UniversePen rejected the request.")
        }
    }
}

enum PenProtocolEvent: Equatable, Sendable {
    case hello(Int)
    case pen(PenSample)
    case deviceStatus(Bool)
    case subscribed
    case ignored
}

/// Bounded JSON-lines decoder; kept on the network queue and reset on reconnect.
struct PenLineDecoder {
    private var buffer = Data()
    static let limit = 1_048_576
    mutating func reset() { buffer.removeAll(keepingCapacity: false) }
    mutating func append(_ chunk: Data) throws -> [PenProtocolEvent] {
        buffer.append(chunk)
        var events: [PenProtocolEvent] = []
        while let newline = buffer.firstIndex(of: 10) {
            let count = buffer.distance(from: buffer.startIndex, to: newline)
            guard count <= Self.limit else { reset(); throw PenProtocolError.oversizedLine }
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if !line.isEmpty { events.append(try Self.decode(line)) }
        }
        guard buffer.count <= Self.limit else { reset(); throw PenProtocolError.oversizedLine }
        return events
    }
    private struct Envelope: Decodable {
        var event: String?; var id: Int?; var error: String?
        var data: EventData?; var result: Subscription?
    }
    private struct Subscription: Decodable { var topics: [String]? }
    private struct EventData: Decodable {
        var api: Int?; var connected: Bool?
        var phase: String?; var x: Double?; var y: Double?; var pressure: Double?
        var screenX: Double?; var screenY: Double?; var tiltX: Double?; var tiltY: Double?; var rotation: Double?; var timestamp: Double?
    }
    static func decode(_ line: Data) throws -> PenProtocolEvent {
        let envelope = try JSONDecoder().decode(Envelope.self, from: line)
        if let error = envelope.error { throw PenProtocolError.server(error) }
        if envelope.id == 1, envelope.result?.topics?.contains("input") == true { return .subscribed }
        guard let data = envelope.data else { return .ignored }
        switch envelope.event {
        case "hello":
            guard let api = data.api else { return .ignored }
            guard api == 1 else { throw PenProtocolError.unsupportedAPI(api) }
            return .hello(api)
        case "pen":
            guard let phase = data.phase, let x = data.x, let y = data.y, let pressure = data.pressure else {
                throw PenProtocolError.invalidSample
            }
            return .pen(try PenSample(phase: phase, x: x, y: y, screenX: data.screenX, screenY: data.screenY,
                                  pressure: pressure, tiltX: data.tiltX, tiltY: data.tiltY,
                                  rotation: data.rotation, timestamp: data.timestamp).validated())
        case "status": return .deviceStatus(data.connected ?? false)
        default: return .ignored
        }
    }
}

/// Opt-in adapter. It never enables the API, changes settings, or writes profiles.
/// Native touch, keyboard and gestures stay in the macOS event path; replaying the
/// API's copies would execute already-configured UniversePen actions twice.
@MainActor final class UniversePenAdapter: ObservableObject {
    @Published private(set) var rawStatus = "Developer API off"
    @Published private var failure: PenConnectionFailure?
    var status: String {
        let label = L(rawStatus)
        guard let failure else { return label }
        return LF("%@ · %@", label, failure.localizedMessage)
    }
    @Published private(set) var connected = false
    @Published private(set) var deviceConnected = false
    @Published private(set) var enabled = false
    var onPen: ((PenSample) -> Void)?
    private var worker: PenConnectionWorker?
    private var session = UUID()

    func enable(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        session = UUID()
        if !enabled {
            onPen?(PenSample(phase: "cancel", x: 0, y: 0, pressure: 0))
            worker?.stop(); worker = nil
            connected = false; deviceConnected = false; rawStatus = "Developer API off"; failure = nil
            return
        }
        rawStatus = "Connecting to 127.0.0.1:47800…"; failure = nil
        let session = self.session
        let worker = PenConnectionWorker { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.enabled, self.session == session else { return }
                switch event {
                case .status(let status, let connected): self.rawStatus = status; self.failure = nil; self.connected = connected
                case .failed(let reason): self.rawStatus = "Disconnected · retrying in 2 s"; self.failure = reason; self.connected = false
                case .pen(let sample): self.onPen?(sample)
                case .device(let available):
                    self.deviceConnected = available
                    if self.connected { self.rawStatus = available ? "UniversePen connected · iPad ready" : "API connected · no iPad"; self.failure = nil }
                }
            }
        }
        self.worker = worker
        worker.start()
    }
    deinit { worker?.stop() }
}

private enum PenConnectionEvent: Sendable {
    case status(String, Bool), failed(PenConnectionFailure), pen(PenSample), device(Bool)
}

/// Typed diagnostics cross the queue boundary without formatting or localization.
private enum PenConnectionFailure: Sendable {
    case noResponse, ended, closed, invalidReply
    case network(String, Int)
    case protocolFailure(PenProtocolError)
    init(_ error: Error) {
        if let error = error as? PenProtocolError { self = .protocolFailure(error); return }
        guard let error = error as? NWError else { self = .invalidReply; return }
        switch error {
        case .posix(let code): self = .network("POSIX", Int(code.rawValue))
        case .dns(let code): self = .network("DNS", Int(code))
        case .tls(let code): self = .network("TLS", Int(code))
        default: self = .invalidReply
        }
    }
    @MainActor var localizedMessage: String {
        switch self {
        case .noResponse: L("No valid UniversePen response")
        case .ended: L("Connection ended")
        case .closed: L("Connection closed")
        case .invalidReply: L("Invalid UniversePen response")
        case .network(let domain, let code): LF("Network error (%@ %d)", domain, code)
        case .protocolFailure(let error): error.localizedMessage
        }
    }
}

/// All mutable transport state lives on this serial queue. The unchecked
/// conformance covers only the queue-confined worker, never UI/document state.
private final class PenConnectionWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.universephoto.pen-input", qos: .userInteractive)
    private var connection: NWConnection?
    private var decoder = PenLineDecoder()
    private var generation = 0
    private var active = false
    private var subscribed = false
    private var greeted = false
    private let deliver: @Sendable (PenConnectionEvent) -> Void
    init(deliver: @escaping @Sendable (PenConnectionEvent) -> Void) { self.deliver = deliver }
    func start() { queue.async { self.active = true; self.connect() } }
    func stop() {
        queue.async {
            self.active = false; self.generation += 1
            self.connection?.cancel(); self.connection = nil; self.decoder.reset()
        }
    }
    private func connect() {
        guard active else { return }
        generation += 1
        let current = generation
        decoder.reset(); subscribed = false; greeted = false
        deliver(.status("Connecting to UniversePen…", false))
        let connection = NWConnection(host: "127.0.0.1", port: 47800, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.active, self.generation == current else { return }
            switch state {
            case .ready:
                self.deliver(.status("TCP connected · checking API…", false))
                self.receive(connection, generation: current)
                // A silent or incompatible local service cannot keep the input route claimed.
                self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, self.active, self.generation == current, !self.subscribed else { return }
                    self.retry(.noResponse)
                }
            case .failed(let error), .waiting(let error): self.retry(PenConnectionFailure(error))
            case .cancelled: self.retry(.ended)
            default: break
            }
        }
        connection.start(queue: queue)
    }
    private func retry(_ reason: PenConnectionFailure) {
        guard active else { return }
        generation += 1
        let retryGeneration = generation
        connection?.cancel(); connection = nil; decoder.reset(); subscribed = false; greeted = false
        deliver(.failed(reason))
        deliver(.device(false))
        // A cancel sample clears any unfinished remote stroke in the canvas.
        deliver(.pen(PenSample(phase: "cancel", x: 0, y: 0, pressure: 0)))
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.active, self.generation == retryGeneration else { return }
            self.connect()
        }
    }
    private func receive(_ connection: NWConnection, generation current: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, self.active, self.generation == current else { return }
            if let data {
                do {
                    for event in try self.decoder.append(data) {
                        switch event {
                        case .hello:
                            self.greeted = true
                            // Subscribe only after validating API v1 greeting.
                            let request = Data("{\"id\":1,\"method\":\"subscribe\",\"params\":{\"topics\":[\"input\",\"status\"]}}\n".utf8)
                            connection.send(content: request, completion: .contentProcessed { [weak self] error in
                                guard let self, self.active, self.generation == current, let error else { return }
                                self.retry(PenConnectionFailure(error))
                            })
                        case .subscribed:
                            guard self.greeted else { continue }
                            self.subscribed = true; self.deliver(.status("UniversePen API connected", true))
                        case .pen(let sample): if self.subscribed { self.deliver(.pen(sample)) }
                        case .deviceStatus(let connected): if self.subscribed { self.deliver(.device(connected)) }
                        case .ignored: break
                        }
                    }
                } catch { self.retry(PenConnectionFailure(error)); return }
            }
            if complete || error != nil { self.retry(error.map(PenConnectionFailure.init) ?? .closed); return }
            self.receive(connection, generation: current)
        }
    }
}
