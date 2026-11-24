import XCTest
import Network
import TafelKit

/// Real HostServer + real client Session/PairingAttempt over 127.0.0.1 (no Bonjour, no capture,
/// no injected events: callbacks are captured instead of posted).
final class SessionIntegrationTests: XCTestCase {
    private func waitForPort(_ get: @escaping () -> UInt16?) -> UInt16? {
        for _ in 0..<100 {
            if let p = get(), p != 0 { return p }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    /// A restarted listener gets a new port (the iPad finds it again through Bonjour).
    private func waitForNewPort(_ server: HostServer, old: UInt16) -> UInt16? {
        for _ in 0..<100 {
            if let p = server.mainPort, p != 0, p != old { return p }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    private var suites: [String] = []

    override func tearDown() {
        for s in suites { UserDefaults.standard.removePersistentDomain(forName: s) }
        suites = []
        super.tearDown()
    }

    /// Defaults of their own per test (never the app's).
    private func testDefaults() -> UserDefaults {
        let name = "tafel-test-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    /// A server whose keys live in memory (never the real keychain), with the same code paths as
    /// the app's keychain store.
    private func makeServer(legacyKey: Data = HostKey.generate()) -> (HostServer, DeviceKeyStore) {
        let server = HostServer()
        server.advertise = false
        let store = DeviceKeyStore(legacyKey: legacyKey, upgraded: true, vault: MemoryVault(), defaults: testDefaults())
        server.keyStore = store
        return (server, store)
    }

    /// Keys and names come back after a restart of the Mac app; unpairing and re-pairing the same
    /// iPad leave exactly one entry.
    func testKeysSurviveARestart() {
        let vault = MemoryVault(), defaults = testDefaults(), shared = HostKey.generate()
        let first = DeviceKeyStore(legacyKey: shared, upgraded: true, vault: vault, defaults: defaults)
        let a = first.issueForLegacy(name: "A", deviceID: "PAD-A")
        let p = first.preparePairing()
        XCTAssertTrue(first.completePairing(id: p.id, name: "B", deviceID: "PAD-B"))
        _ = first.issueForLegacy(name: "B again", deviceID: "PAD-B")   // same iPad: replaces its entry

        let second = DeviceKeyStore(legacyKey: shared, upgraded: true, vault: vault, defaults: defaults)
        XCTAssertEqual(Set(second.all.map(\.deviceID)), ["PAD-A", "PAD-B"])
        XCTAssertTrue(second.psks().contains { $0.key == a.key && $0.identity == HostKey.deviceIdentity(a.id) })
        XCTAssertTrue(second.hasLegacyPairings)
        XCTAssertEqual(second.remove(a.id), "PAD-A")
        XCTAssertNil(vault.key("ipad-key-\(a.id)"))

        let third = DeviceKeyStore(legacyKey: shared, upgraded: true, vault: vault, defaults: defaults)
        XCTAssertEqual(third.all.map(\.name), ["B again"])
        XCTAssertNotEqual(third.retireLegacy(), shared)
        XCTAssertFalse(DeviceKeyStore(legacyKey: shared, upgraded: true, vault: vault, defaults: defaults).hasLegacyPairings)
    }

    func testPairThenStreamAndInput() throws {
        let (server, store) = makeServer()
        server.hostID = "HOST-1"
        server.hostName = "Test-Mac"
        let prepared = store.preparePairing()
        server.start()
        let code = PairingCode.generate()
        server.startPairing(code: code, grantKey: prepared.key, keyID: prepared.id)
        let pairPort = try XCTUnwrap(waitForPort { server.pairingPort })
        let mainPort = try XCTUnwrap(waitForPort { server.mainPort })

        // 1. Wrong code is rejected.
        let rejected = expectation(description: "wrong code rejected")
        PairingAttempt().run(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: pairPort)!),
                             code: PairingCode.generate(), deviceID: "PAD", deviceName: "Test-iPad") { r in
            if case .failure = r { rejected.fulfill() }
        }
        wait(for: [rejected], timeout: 12)

        // 2. Correct code yields the host key.
        let paired = expectation(description: "paired")
        var grant: PairGrant?
        PairingAttempt().run(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: pairPort)!),
                             code: code, deviceID: "PAD", deviceName: "Test-iPad") { r in
            if case .success(let g) = r { grant = g; paired.fulfill() }
        }
        wait(for: [paired], timeout: 12)
        XCTAssertEqual(grant?.hostID, "HOST-1")
        let key = try XCTUnwrap(grant.flatMap { Data(base64Encoded: $0.keyBase64) })
        // The iPad gets its own key, not the shared one, and is listed under its name.
        XCTAssertEqual(key, prepared.key)
        XCTAssertEqual(grant?.keyID, prepared.id)
        XCTAssertEqual(store.all.map(\.name), ["Test-iPad"])

        // 3. Session with the granted key: hostInfo, config, pen, shortcut, video.
        let gotConfig = expectation(description: "config")
        let gotPen = expectation(description: "pen")
        let gotShortcut = expectation(description: "shortcut")
        let gotVideo = expectation(description: "video connection")
        server.onClientConfig = { c in if c.viewPixelWidth == 2360 { gotConfig.fulfill() } }
        server.onPen = { s in if s.phase == .down && abs(s.pressure - 0.5) < 0.001 { gotPen.fulfill() } }
        server.onShortcut = { s in if s == Shortcut("z", .command) { gotShortcut.fulfill() } }
        server.onVideoConnected = { gotVideo.fulfill() }

        let renderer = VideoRenderer()
        let session = Session(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: mainPort)!),
                              key: key, keyID: grant?.keyID, deviceID: "PAD", deviceName: "Test-iPad", renderer: renderer)
        session.onRekey = { _ in XCTFail("an iPad with its own key gets no new one") }
        let connected = expectation(description: "connected")
        session.onConnected = { connected.fulfill() }
        session.start()
        session.send(config: ClientConfig(viewPixelWidth: 2360, viewPixelHeight: 1640, quality: StreamQuality()))
        wait(for: [connected, gotConfig, gotVideo], timeout: 10)
        session.send(PenSample(phase: .down, x: 0.5, y: 0.5, pressure: 0.5))
        session.send(Shortcut("z", .command))
        wait(for: [gotPen, gotShortcut], timeout: 5)

        // 4. Timing reports arrive (ping/pong).
        let timed = expectation(description: "timing")
        timed.assertForOverFulfill = false
        session.onTiming = { t in if t.rttMs > 0 { timed.fulfill() } }
        wait(for: [timed], timeout: 5)

        session.close()
    }

    func testSessionWithWrongKeyFails() throws {
        let (server, _) = makeServer()
        server.start()
        let port = try XCTUnwrap(waitForPort { server.mainPort })
        let session = Session(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
                              key: HostKey.generate(), keyID: nil, deviceID: "X", deviceName: "X", renderer: VideoRenderer())
        let failed = expectation(description: "failed")
        session.onConnected = { XCTFail("must not connect") }
        session.onClosed = { reason in if reason != nil { failed.fulfill() } }
        session.start()
        wait(for: [failed], timeout: 12)
    }

    /// A second iPad (other device ID) becomes an input-only tablet: it is told so, gets no video,
    /// and its Pencil arrives on the extra-tablet path while the first iPad stays connected.
    func testSecondIPadBecomesTablet() throws {
        let key = HostKey.generate()
        let (server, _) = makeServer(legacyKey: key)
        server.start()
        let port = try XCTUnwrap(waitForPort { server.mainPort })
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        let first = Session(endpoint: endpoint, key: key, keyID: nil, deviceID: "PAD-A", deviceName: "A", renderer: VideoRenderer())
        let firstUp = expectation(description: "first connected")
        first.onConnected = { firstUp.fulfill() }
        first.start()
        wait(for: [firstUp], timeout: 10)

        let extraPen = expectation(description: "extra pen")
        let names = expectation(description: "extras listed")
        server.onExtraPen = { s in if s.phase == .down { extraPen.fulfill() } }
        server.onPen = { _ in XCTFail("the extra iPad's Pencil must not use the main path") }
        server.onExtrasChanged = { n in if n == ["B"] { names.fulfill() } }

        let second = Session(endpoint: endpoint, key: key, keyID: nil, deviceID: "PAD-B", deviceName: "B", renderer: VideoRenderer())
        let secondInfo = expectation(description: "second told it is secondary")
        second.onHostInfo = { info in if info.secondary == true { secondInfo.fulfill() } }
        second.onConnected = { second.send(PenSample(phase: .down, x: 0.5, y: 0.5, pressure: 0.4)) }
        var firstClosed = false
        first.onClosed = { _ in firstClosed = true }
        second.start()
        wait(for: [secondInfo, extraPen, names], timeout: 10)
        XCTAssertFalse(firstClosed, "the first iPad must stay connected")
        second.close()
        first.close()
    }

    func testClipboardBothWays() throws {
        let key = HostKey.generate()
        let (server, _) = makeServer(legacyKey: key)
        server.start()
        let port = try XCTUnwrap(waitForPort { server.mainPort })
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        let toMac = expectation(description: "iPad clipboard reached the Mac")
        server.onClipboard = { item in if item.text == "vom iPad ✏️" { toMac.fulfill() } }
        server.clipboardProvider = { .text("vom Mac 🖥") }

        let pad = Session(endpoint: endpoint, key: key, keyID: nil, deviceID: "PAD-C", deviceName: "C", renderer: VideoRenderer())
        let fromMac = expectation(description: "Mac clipboard reached the iPad")
        pad.onClipboard = { item in if item.text == "vom Mac 🖥" { fromMac.fulfill() } }
        pad.onConnected = {
            pad.send(clipboard: .text("vom iPad ✏️"))
            pad.requestClipboard()
        }
        pad.start()
        wait(for: [toMac, fromMac], timeout: 10)
        pad.close()
    }

    func testScreenshotRequestReachesIPad() throws {
        let key = HostKey.generate()
        let (server, _) = makeServer(legacyKey: key)
        server.start()
        let port = try XCTUnwrap(waitForPort { server.mainPort })
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let fake = Data(repeating: 0xAB, count: 3 * 1024 * 1024)   // a big image must arrive whole
        server.screenshotProvider = { done in DispatchQueue.global().async { done(fake) } }

        let pad = Session(endpoint: endpoint, key: key, keyID: nil, deviceID: "PAD-D", deviceName: "D", renderer: VideoRenderer())
        let got = expectation(description: "screenshot arrived")
        pad.onScreenshot = { d in if d == fake { got.fulfill() } }
        pad.onConnected = { pad.requestScreenshot() }
        pad.start()
        wait(for: [got], timeout: 10)
        pad.close()
    }

    /// An iPad paired before every iPad had its own key connects with the shared key, gets its own
    /// key over that connection and can connect with it afterwards.
    func testOlderPairingMovesToItsOwnKey() throws {
        let shared = HostKey.generate()
        let (server, store) = makeServer(legacyKey: shared)
        server.start()
        let port = try XCTUnwrap(waitForPort { server.mainPort })
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        let old = Session(endpoint: endpoint, key: shared, keyID: nil, deviceID: "PAD-E", deviceName: "E", renderer: VideoRenderer())
        let rekeyed = expectation(description: "own key arrived")
        var grant: PairGrant?
        old.onRekey = { g in grant = g; rekeyed.fulfill() }
        var oldClosed = false
        old.onClosed = { _ in oldClosed = true }
        old.start()
        wait(for: [rekeyed], timeout: 10)
        let g = try XCTUnwrap(grant)
        XCTAssertEqual(store.all.map(\.id), [try XCTUnwrap(g.keyID)])

        // The listener learns the key a moment later (restarted, on a new port); the running
        // session must not notice.
        let newPort = try XCTUnwrap(waitForNewPort(server, old: port))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(oldClosed, "the open session survives the listener restart")
        old.close()
        let renewed = Session(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: newPort)!), key: try XCTUnwrap(Data(base64Encoded: g.keyBase64)), keyID: g.keyID,
                              deviceID: "PAD-E", deviceName: "E", renderer: VideoRenderer())
        let up = expectation(description: "connected with its own key")
        renewed.onConnected = { up.fulfill() }
        renewed.onRekey = { _ in XCTFail("no second rekey") }
        renewed.start()
        wait(for: [up], timeout: 10)
        renewed.close()
    }

    /// Unpairing one iPad stops its key at once; another iPad keeps working.
    func testUnpairingOneIPadKeepsTheOther() throws {
        let (server, store) = makeServer()
        let a = store.issueForLegacy(name: "A", deviceID: "PAD-A")
        let b = store.issueForLegacy(name: "B", deviceID: "PAD-B")
        server.start()
        let port = try XCTUnwrap(waitForPort { server.mainPort })

        XCTAssertEqual(store.remove(a.id), "PAD-A")
        server.start()
        let newPort = try XCTUnwrap(waitForNewPort(server, old: port))
        let endpoint2 = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: newPort)!)

        let gone = Session(endpoint: endpoint2, key: a.key, keyID: a.id, deviceID: "PAD-A", deviceName: "A", renderer: VideoRenderer())
        let refused = expectation(description: "unpaired iPad refused")
        gone.onConnected = { XCTFail("an unpaired iPad must not connect") }
        gone.onClosed = { reason in if reason != nil { refused.fulfill() } }
        gone.start()
        wait(for: [refused], timeout: 12)

        let kept = Session(endpoint: endpoint2, key: b.key, keyID: b.id, deviceID: "PAD-B", deviceName: "B", renderer: VideoRenderer())
        let up = expectation(description: "other iPad still connects")
        kept.onConnected = { up.fulfill() }
        kept.start()
        wait(for: [up], timeout: 10)
        kept.close()
    }
}
