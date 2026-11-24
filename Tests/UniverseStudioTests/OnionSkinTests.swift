import Testing
import CoreGraphics
import Foundation
@testable import UniverseStudio

struct OnionSkinTests {
    @Test func ghostsFadeWithDistanceNearestLast() {
        let o = OnionSettings(before: 2, after: 1, opacity: 0.4)
        let g = o.ghosts(current: 3, count: 6, loop: false)
        #expect(g.map(\.index) == [1, 2, 4])
        #expect(g[0].alpha < g[1].alpha && abs(g[1].alpha - 0.4) < 1e-9 && g[0].isBefore && !g[2].isBefore)
    }

    @Test func endsClipOrWrap() {
        let o = OnionSettings(before: 2, after: 2)
        #expect(o.ghosts(current: 0, count: 4, loop: false).map(\.index) == [2, 1])
        #expect(o.ghosts(current: 0, count: 4, loop: true).map(\.index) == [2, 3, 1], "wrapped frames are shown once")
        #expect(o.ghosts(current: 0, count: 1, loop: true).isEmpty)
        #expect(OnionSettings(before: 0, after: 0).ghosts(current: 1, count: 3, loop: true).isEmpty)
    }

    @Test func defaultsAndTintKeepsShape() throws {
        let d = try #require(UserDefaults(suiteName: "onion-test-\(UUID().uuidString)"))
        #expect(OnionSettings(defaults: d) == OnionSettings())
        d.set(3, forKey: "onionAfter"); d.set(false, forKey: "onionTinted")
        #expect(OnionSettings(defaults: d).after == 3 && !OnionSettings(defaults: d).tinted)
        let ctx = try #require(Renderer.context(width: 4, height: 1))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        let src = try #require(ctx.makeImage())
        let t = try #require(OnionSettings.tint(src, color: OnionSettings.beforeColor))
        let b = try #require(PixelOps.bitmap(t))
        #expect(b.bytes[0] > 100 && b.bytes[3] == 255, "black turns reddish")
        #expect(b.bytes[2 * 4 + 3] == 0, "transparent stays transparent")
    }
}
