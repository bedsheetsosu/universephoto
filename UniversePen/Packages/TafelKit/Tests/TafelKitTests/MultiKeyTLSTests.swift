import XCTest
import Network
@testable import TafelKit

/// Can one listener hold several pre-shared keys (one per paired iPad) and pick the right one
/// by the identity the client sends? Real TLS over localhost.
final class MultiKeyTLSTests: XCTestCase {
    private func listener(_ keys: [(Data, String)]) throws -> (NWListener, DispatchQueue) {
        let q = DispatchQueue(label: "test.multi.listener")
        let first = keys[0]
        let params = TafelNetwork.parameters(psk: first.0, identity: first.1, video: false)
        let tls = params.defaultProtocolStack.applicationProtocols.first as! NWProtocolTLS.Options
        for (k, id) in keys.dropFirst() {
            let kd = k.withUnsafeBytes { DispatchData(bytes: $0) }
            let idd = Data(id.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
            sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, kd as __DispatchData, idd as __DispatchData)
        }
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params, on: .any)
        var held: [FramedConnection] = []
        l.newConnectionHandler = { c in
            let fc = FramedConnection(c, queue: q)
            held.append(fc)
            fc.onFrame = { f in
                if f.type == .ping, let p = try? Ping(decoding: f.payload) { fc.send(.pong, Pong(clientTime: p.clientTime, hostTime: 1).encoded()) }
            }
            fc.start()
        }
        let ready = expectation(description: "ready")
        l.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        l.start(queue: q)
        wait(for: [ready], timeout: 5)
        return (l, q)
    }

    /// true = got a pong back, false = the handshake failed.
    private func tryConnect(port: NWEndpoint.Port, key: Data, identity: String) -> Bool {
        let done = expectation(description: "done \(identity)")
        var ok = false
        let c = FramedConnection(NWConnection(host: "127.0.0.1", port: port,
                                              using: TafelNetwork.parameters(psk: key, identity: identity, video: false)),
                                 queue: DispatchQueue(label: "test.multi.client.\(identity)"))
        c.onFrame = { f in if f.type == .pong { ok = true; done.fulfill() } }
        c.onState = { s in
            switch s {
            case .ready: c.send(.ping, Ping(clientTime: 3).encoded())
            case .waiting: c.cancel()
            default: break
            }
        }
        c.onClose = { e in if e != nil, !ok { done.fulfill() } }
        c.start()
        wait(for: [done], timeout: 12)
        c.cancel()
        return ok
    }

    func testListenerPicksTheKeyByIdentity() throws {
        let a = HostKey.generate(), b = HostKey.generate()
        let (l, _) = try listener([(a, "dev-A"), (b, "dev-B")])
        defer { l.cancel() }
        guard let port = l.port else { return XCTFail("no port") }
        XCTAssertTrue(tryConnect(port: port, key: b, identity: "dev-B"), "second key")
        XCTAssertTrue(tryConnect(port: port, key: a, identity: "dev-A"), "first key")
        XCTAssertFalse(tryConnect(port: port, key: HostKey.generate(), identity: "dev-C"), "unknown identity")
        XCTAssertFalse(tryConnect(port: port, key: a, identity: "dev-B"), "key of another identity")
    }

    func testGrantAndHelloCarryTheKeyID() throws {
        let own = PairGrant(hostID: "H", hostName: "Mac", keyBase64: "x", keyID: "42")
        XCTAssertEqual(own.identity, HostKey.deviceIdentity("42"))
        XCTAssertEqual(try JSONWire.decode(PairGrant.self, JSONWire.encode(own)), own)
        // A grant from before every iPad had its own key means the shared key.
        XCTAssertEqual(PairGrant(hostID: "H", hostName: "Mac", keyBase64: "x").identity, HostKey.pskIdentity)
        let hello = Hello(role: .control, deviceID: "D", deviceName: "iPad", keyID: "42")
        XCTAssertEqual(try JSONWire.decode(Hello.self, JSONWire.encode(hello)).keyID, "42")
    }
}
