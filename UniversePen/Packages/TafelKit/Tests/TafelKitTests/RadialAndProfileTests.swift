import XCTest
@testable import TafelKit

final class RadialAndProfileTests: XCTestCase {
    func testRadialArcPicksByDirection() {
        let r = RadialMenuLayout.radius(count: 5)
        XCTAssertEqual(RadialMenuLayout.item(dx: 0, dy: -r, count: 5), 2)      // straight up = middle item
        XCTAssertEqual(RadialMenuLayout.item(dx: 0, dy: -r, count: 4), 2)      // even count: up lands between 1 and 2, rounds to 2
        XCTAssertNil(RadialMenuLayout.item(dx: 0, dy: r, count: 5))            // below the tip: beyond the arc
        XCTAssertNil(RadialMenuLayout.item(dx: 5, dy: 5, count: 5))            // dead zone
        XCTAssertNil(RadialMenuLayout.item(dx: 500, dy: 0, count: 5))          // far outside
        // Facing down (menu opened near the top edge): straight down is the middle.
        XCTAssertEqual(RadialMenuLayout.item(dx: 0, dy: r, count: 5, facing: .pi / 2), 2)
    }

    func testItemCentresMapBackToTheirItem() {
        for facing in [RadialMenuLayout.up, 0, .pi / 2, .pi, -.pi / 4] {
            for n in 1...12 {
                for i in 0..<n {
                    let o = RadialMenuLayout.offset(of: i, count: n, facing: facing)
                    XCTAssertEqual(RadialMenuLayout.item(dx: o.x, dy: o.y, count: n, facing: facing), i, "n=\(n) i=\(i) f=\(facing)")
                }
            }
        }
    }

    func testRadialButtonsDontOverlapAndArcStaysOpen() {
        for n in 2...12 {
            let a = RadialMenuLayout.offset(of: 0, count: n), b = RadialMenuLayout.offset(of: 1, count: n)
            let gap = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
            XCTAssertGreaterThanOrEqual(gap, RadialMenuLayout.buttonSize, "n=\(n)")
            XCTAssertLessThanOrEqual(RadialMenuLayout.step(count: n) * Double(n - 1), 261 * .pi / 180, "n=\(n)")
        }
    }

    func testRadialFacingKeepsArcOnScreen() {
        let f = { (x: Double, y: Double) in RadialMenuLayout.facing(x: x, y: y, width: 1180, height: 820, count: 6) }
        XCTAssertEqual(f(600, 500), RadialMenuLayout.preferred, accuracy: 1e-9)
        XCTAssertEqual(f(600, 40), .pi / 2, accuracy: 1e-9)          // near the top: opens downwards
        XCTAssertEqual(f(30, 500), 0, accuracy: 1e-9)                // near the left: opens to the right
        XCTAssertEqual(f(1160, 500), .pi, accuracy: 1e-9)            // near the right: opens to the left
    }

    func testPerAppProfileOverridesOnlyPencilPart() {
        var s = InputSettings()
        var p = s.penProfile
        p.squeeze = .radialMenu
        p.positionSmoothing = 0.7
        s.appPenProfiles["com.seriflabs.affinity"] = p
        let e = s.effective(for: "com.seriflabs.affinity")
        XCTAssertEqual(e.squeeze, .radialMenu)
        XCTAssertEqual(e.positionSmoothing, 0.7)
        XCTAssertEqual(e.zoomMethod, s.zoomMethod)
        XCTAssertEqual(s.effective(for: "com.other"), s)
        XCTAssertEqual(s.effective(for: nil), s)
    }

    func testOldSettingsDecodeAndNewOnesRoundTrip() throws {
        let old = try JSONDecoder().decode(InputSettings.self, from: Data(#"{"squeeze":{"shortcut":{"_0":{"key":"z","modifiers":1}}}}"#.utf8))
        XCTAssertEqual(old.radialMenu.count, InputSettings.defaultRadialMenu.count)
        var s = InputSettings()
        s.squeeze = .radialMenu
        s.appPenProfiles["x"] = s.penProfile
        XCTAssertEqual(try JSONDecoder().decode(InputSettings.self, from: JSONEncoder().encode(s)), s)
    }

    func testClientConfigBatteryRoundTrip() throws {
        let c = ClientConfig(viewPixelWidth: 1, viewPixelHeight: 1, quality: StreamQuality(), batteryLevel: 0.42, batteryCharging: true)
        XCTAssertEqual(try JSONWire.decode(ClientConfig.self, JSONWire.encode(c)), c)
    }
}

final class GameModeAndSourceTests: XCTestCase {
    func testGameAppDropsSmoothingAndRaisesQuality() {
        var s = InputSettings()
        s.positionSmoothing = 0.5
        s.gameApps["sh.ppy.osu.lazer"] = "osu!"
        XCTAssertEqual(s.effective(for: "sh.ppy.osu.lazer").positionSmoothing, 0)
        XCTAssertEqual(s.effective(for: "sh.ppy.osu.lazer").pressureSmoothing, 0)
        XCTAssertEqual(s.effective(for: "com.other").positionSmoothing, 0.5)
        let q = StreamQuality(fps: 30, resolutionScale: 0.5, adaptive: true, fullSource: false).gameMode
        XCTAssertEqual(q.fps, 60); XCTAssertEqual(q.resolutionScale, 1)
        XCTAssertTrue(q.fullSource); XCTAssertFalse(q.adaptive); XCTAssertGreaterThanOrEqual(q.bitrateMbps, 60)
    }

    func testSourceMessagesRoundTrip() throws {
        let l = SourceList(mode: "window", modes: [SourceOption(id: "display", title: "Display")],
                           displays: [SourceOption(id: "1", title: "Built-in")], selectedDisplay: "1",
                           windows: [SourceOption(id: "42", title: "Affinity – x")], selectedWindow: "42")
        XCTAssertEqual(try JSONWire.decode(SourceList.self, JSONWire.encode(l)), l)
        let sel = SourceSelection(mode: "window", window: "42")
        XCTAssertEqual(try JSONWire.decode(SourceSelection.self, JSONWire.encode(sel)), sel)
    }
}

final class TabletAreaTests: XCTestCase {
    func testLockKeepsAspectInsideAndCentre() {
        let size = CGSize(width: 1180, height: 820)
        let a = TabletArea(x: 0.1, y: 0.1, width: 0.5, height: 0.5).locked(to: 1710.0 / 1112.0, in: size)
        let r = a.rect(in: size)
        XCTAssertEqual(Double(r.width / r.height), 1710.0 / 1112.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(r.minX, 0); XCTAssertLessThanOrEqual(r.maxX, size.width + 0.001)
        XCTAssertGreaterThanOrEqual(r.minY, 0); XCTAssertLessThanOrEqual(r.maxY, size.height + 0.001)
        XCTAssertEqual(Double(r.midX), 0.35 * 1180, accuracy: 0.5)
    }

    func testHugeAreaIsClampedToTheView() {
        let size = CGSize(width: 1180, height: 820)
        let r = TabletArea(x: 0, y: 0, width: 1, height: 1).locked(to: 16.0 / 9.0, in: size).rect(in: size)
        XCTAssertLessThanOrEqual(r.width, size.width + 0.001)
        XCTAssertLessThanOrEqual(r.height, size.height + 0.001)
    }

    func testAppBoundPresetWinsWhileAppInFront() {
        var s = InputSettings()
        s.tabletArea = TabletArea(x: 0, y: 0, width: 1, height: 1)
        let small = TabletArea(x: 0.3, y: 0.3, width: 0.3, height: 0.2)
        s.tabletPresets = [TabletPreset(name: "osu!", area: small, lockAspect: false, appBundleID: "sh.ppy.osu.lazer", appName: "osu!")]
        XCTAssertEqual(s.effective(for: "sh.ppy.osu.lazer").tabletArea, small)
        XCTAssertEqual(s.effective(for: "com.seriflabs.affinityphoto2").tabletArea, s.tabletArea)
        XCTAssertEqual(s.effective(for: nil).tabletArea, s.tabletArea)
    }

    func testDefaultTabletAreaIsFullArea() {
        XCTAssertEqual(InputSettings().tabletArea, .full)
        XCTAssertTrue(TabletPreset.fullArea.matches(.full))
        XCTAssertTrue(TabletPreset.fullArea.isBuiltIn)
    }

    func testProfilesTravelButNeverRestartTheStream() throws {
        let a = ClientConfig(viewPixelWidth: 10, viewPixelHeight: 10, quality: StreamQuality())
        var b = a
        b.profiles = [ProfileSummary(id: "1", name: "Drawing"), ProfileSummary(id: "2", name: "osu!")]
        b.activeProfile = "2"
        XCTAssertTrue(b.sameStream(as: a))
        XCTAssertEqual(try JSONWire.decode(ClientConfig.self, JSONWire.encode(b)), b)
        // An older iPad sends no profiles at all.
        XCTAssertNil(try JSONWire.decode(ClientConfig.self, JSONWire.encode(a)).profiles)
    }

    func testTabletModeRestartsStream() {
        let a = ClientConfig(viewPixelWidth: 10, viewPixelHeight: 10, quality: StreamQuality())
        var b = a; b.tabletMode = true
        XCTAssertFalse(b.sameStream(as: a))
    }
}

final class PluginWireTests: XCTestCase {
    func testPluginActionAndButtonRoundTrip() throws {
        var s = InputSettings()
        s.squeeze = .plugin("squeeze-scroll/toggle")
        s.radialMenu.append(ShortcutButton(title: "Layer", shortcut: Shortcut("n", [.command, .shift]), pluginAction: "x/new-layer"))
        XCTAssertEqual(try JSONDecoder().decode(InputSettings.self, from: JSONEncoder().encode(s)), s)
        let old = try JSONDecoder().decode(ShortcutButton.self, from: Data(#"{"id":"8D2E3F4A-1B2C-4D5E-8F90-123456789ABC","title":"Undo","shortcut":{"key":"z","modifiers":1}}"#.utf8))
        XCTAssertNil(old.pluginAction)
        let a = [PluginActionInfo(id: "p/a", title: "A", icon: "star", plugin: "P")]
        XCTAssertEqual(try JSONWire.decode([PluginActionInfo].self, JSONWire.encode(a)), a)
    }
}

final class TabletExtrasTests: XCTestCase {
    func testRotatedAreaMapsCornersAndCentre() {
        let size = CGSize(width: 1000, height: 800)
        var a = TabletArea(x: 0.2, y: 0.25, width: 0.5, height: 0.5)
        a.rotation = 90
        let c = a.corners(in: size)
        // Rotated corner "top-left" maps back to (0, 0) of the area.
        let n = a.normalized(c[0], in: size)
        XCTAssertEqual(Double(n.x), 0, accuracy: 0.001); XCTAssertEqual(Double(n.y), 0, accuracy: 0.001)
        let m = a.normalized(CGPoint(x: a.rect(in: size).midX, y: a.rect(in: size).midY), in: size)
        XCTAssertEqual(Double(m.x), 0.5, accuracy: 0.001); XCTAssertEqual(Double(m.y), 0.5, accuracy: 0.001)
        let br = a.normalized(c[2], in: size)
        XCTAssertEqual(Double(br.x), 1, accuracy: 0.001); XCTAssertEqual(Double(br.y), 1, accuracy: 0.001)
    }

    func testOldAreaWithoutRotationDecodes() throws {
        let a = try JSONDecoder().decode(TabletArea.self, from: Data(#"{"x":0.1,"y":0.2,"width":0.3,"height":0.4}"#.utf8))
        XCTAssertEqual(a.rotation, 0); XCTAssertEqual(a.width, 0.3)
    }

    func testTipGate() {
        var g = TipGate()
        XCTAssertEqual(g.phase(for: .down, pressure: 0.1, threshold: 0.3), .hover)
        XCTAssertEqual(g.phase(for: .move, pressure: 0.35, threshold: 0.3), .down)
        XCTAssertEqual(g.phase(for: .move, pressure: 0.25, threshold: 0.3), .move)    // hysteresis
        XCTAssertEqual(g.phase(for: .move, pressure: 0.2, threshold: 0.3), .up)
        XCTAssertEqual(g.phase(for: .up, pressure: 0, threshold: 0.3), nil)
        var off = TipGate()
        XCTAssertEqual(off.phase(for: .down, pressure: 0.01, threshold: 0), .down)
    }

    func testKeyColumnVerticalPosition() {
        var k = TabletKeys()
        k.vertical = 0
        XCTAssertEqual(Double(k.frames(in: CGSize(width: 1180, height: 820))[0].minY), 22, accuracy: 0.5)
        k.vertical = 1
        let f = k.frames(in: CGSize(width: 1180, height: 820))
        XCTAssertEqual(Double(f.last!.maxY), 820 - 22, accuracy: 0.5)
    }

    func testKeyRowAtTheTop() {
        var k = TabletKeys(); k.side = .top; k.vertical = 0
        let f = k.frames(in: CGSize(width: 1180, height: 820))
        XCTAssertEqual(Double(f[0].minY), 22, accuracy: 0.5)
        XCTAssertEqual(Double(f[0].minX), 22, accuracy: 0.5)
        XCTAssertEqual(Double(f[1].minY), Double(f[0].minY), accuracy: 0.01)   // side by side
        XCTAssertGreaterThan(f[1].minX, f[0].maxX)
    }

    func testFreelyPlacedKeys() {
        var k = TabletKeys()
        k.keys[0].x = 0.05; k.keys[0].y = 0.5      // W far left
        k.keys[1].x = 0.95; k.keys[1].y = 0.5      // E far right
        let f = k.frames(in: CGSize(width: 1000, height: 800))
        XCTAssertEqual(Double(f[0].midX), 60, accuracy: 0.5)     // clamped so the key stays on screen
        XCTAssertEqual(Double(f[1].midX), 940, accuracy: 0.5)
        XCTAssertTrue(k.anyMoved)
        let old = try? JSONDecoder().decode(TabletKey.self, from: Data(#"{"id":"8D2E3F4A-1B2C-4D5E-8F90-123456789ABC","title":"Z","key":"z"}"#.utf8))
        XCTAssertNil(old?.x)
    }

    func testDoubleTapToClick() {
        var g = DoubleTapClickGate()
        XCTAssertFalse(g.begin(at: CGPoint(x: 100, y: 100), time: 0))      // first touch: pointer only
        g.end(at: CGPoint(x: 300, y: 200), time: 1.0)
        XCTAssertTrue(g.begin(at: CGPoint(x: 310, y: 205), time: 1.2))      // quick, close: click
        g.end(at: CGPoint(x: 400, y: 300), time: 2.0)
        XCTAssertFalse(g.begin(at: CGPoint(x: 400, y: 300), time: 2.1))     // after a click: pointer again
        g.end(at: CGPoint(x: 400, y: 300), time: 2.2)
        XCTAssertFalse(g.begin(at: CGPoint(x: 400, y: 300), time: 3.0))     // too late
        g.end(at: CGPoint(x: 0, y: 0), time: 3.1)
        XCTAssertFalse(g.begin(at: CGPoint(x: 200, y: 200), time: 3.2))     // too far
    }

    func testProfileRoundTrip() throws {
        var s = InputSettings(); s.tabletMode = true; s.tipThreshold = 0.2
        let p = SettingsProfile(name: "osu!", settings: s, quality: StreamQuality(fps: 60))
        XCTAssertEqual(try JSONDecoder().decode(SettingsProfile.self, from: JSONEncoder().encode(p)), p)
    }

    func testKeyFramesOnTheChosenSide() {
        var k = TabletKeys(); k.side = .right
        let f = k.frames(in: CGSize(width: 1180, height: 820))
        XCTAssertEqual(f.count, 2)
        XCTAssertGreaterThan(f[0].minX, 1000)
        XCTAssertLessThan(f[0].maxY, f[1].minY)
    }

    func testSqueezeOpensTheRadialMenuByDefault() throws {
        XCTAssertEqual(InputSettings().squeeze, .radialMenu)
        XCTAssertEqual(try JSONDecoder().decode(InputSettings.self, from: Data("{}".utf8)).squeeze, .radialMenu)
    }
}
