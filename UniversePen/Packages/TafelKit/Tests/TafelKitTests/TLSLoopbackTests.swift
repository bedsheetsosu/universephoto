import XCTest
import Network
@testable import TafelKit

/// Real TLS-PSK handshake over localhost: proves frames arrive with the right key and that a
/// wrong key cannot connect. Nothing leaves the machine.
final class TLSLoopbackTests: XCTestCase {
    private func makeListener(key: Data, onFrame: @escaping (Frame, FramedConnection) -> Void) throws -> (NWListener, DispatchQueue, [FramedConnection]) {
        let q = DispatchQueue(label: "test.listener")
        let params = TafelNetwork.parameters(psk: key, identity: HostKey.pskIdentity, video: false)
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params, on: .any)
        var held: [FramedConnection] = []
        l.newConnectionHandler = { c in
            let fc = FramedConnection(c, queue: q)
            held.append(fc)
            fc.onFrame = { onFrame($0, fc) }
            fc.start()
        }
        return (l, q, held)
    }

    private func waitReady(_ l: NWListener, _ q: DispatchQueue) -> NWEndpoint.Port? {
        let ready = expectation(description: "listener ready")
        l.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        l.start(queue: q)
        wait(for: [ready], timeout: 5)
        return l.port
    }

    func testFramesFlowWithCorrectKey() throws {
        let key = HostKey.generate()
        let got = expectation(description: "pong")
        let (l, q, _) = try makeListener(key: key) { frame, conn in
            if frame.type == .ping, let p = try? Ping(decoding: frame.payload) {
                conn.send(.pong, Pong(clientTime: p.clientTime, hostTime: 42).encoded())
            }
        }
        guard let port = waitReady(l, q) else { return XCTFail("no port") }
        defer { l.cancel() }

        let client = FramedConnection(NWConnection(host: "127.0.0.1", port: port,
                                                   using: TafelNetwork.parameters(psk: key, identity: HostKey.pskIdentity, video: false)),
                                      queue: DispatchQueue(label: "test.client"))
        client.onFrame = { f in
            if f.type == .pong, let p = try? Pong(decoding: f.payload), p.clientTime == 7, p.hostTime == 42 { got.fulfill() }
        }
        client.onState = { if case .ready = $0 { client.send(.ping, Ping(clientTime: 7).encoded()) } }
        client.start()
        wait(for: [got], timeout: 5)
        client.cancel()
    }

    func testLargeFrameIsReassembled() throws {
        let key = HostKey.generate()
        let blob = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let got = expectation(description: "blob")
        let (l, q, _) = try makeListener(key: key) { frame, _ in
            if frame.type == .videoFrame, let v = try? VideoFrame(decoding: frame.payload), v.data == blob { got.fulfill() }
        }
        guard let port = waitReady(l, q) else { return XCTFail("no port") }
        defer { l.cancel() }
        let client = FramedConnection(NWConnection(host: "127.0.0.1", port: port,
                                                   using: TafelNetwork.parameters(psk: key, identity: HostKey.pskIdentity, video: true)),
                                      queue: DispatchQueue(label: "test.client2"))
        client.onState = { if case .ready = $0 { client.send(.videoFrame, VideoFrame(isKeyframe: true, captureTime: 1, data: blob).encoded()) } }
        client.start()
        wait(for: [got], timeout: 10)
        client.cancel()
    }

    func testWrongKeyCannotConnect() throws {
        let (l, q, _) = try makeListener(key: HostKey.generate()) { _, _ in XCTFail("frame with wrong key") }
        guard let port = waitReady(l, q) else { return XCTFail("no port") }
        defer { l.cancel() }
        let closed = expectation(description: "rejected")
        let params = TafelNetwork.parameters(psk: HostKey.generate(), identity: HostKey.pskIdentity, video: false)
        let client = FramedConnection(NWConnection(host: "127.0.0.1", port: port, using: params), queue: DispatchQueue(label: "test.client3"))
        var becameReady = false
        client.onState = { state in
            switch state {
            case .ready: becameReady = true
            case .waiting: client.cancel()
            default: break
            }
        }
        // A bad PSK surfaces as a TLS error (e.g. -9820 bad record MAC) through onClose.
        client.onClose = { e in if e != nil { closed.fulfill() } }
        client.start()
        wait(for: [closed], timeout: 12)
        XCTAssertFalse(becameReady)
    }
}
