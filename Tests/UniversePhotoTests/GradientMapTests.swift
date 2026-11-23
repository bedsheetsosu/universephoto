import CoreGraphics
import Foundation
import Testing
@testable import UniversePhoto

struct GradientMapTests {
    @Test func darkAndLightGoToTheirColours() throws {
        let ctx = try #require(Renderer.context(width: 40, height: 20))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 20, y: 0, width: 20, height: 10))
        let image = try #require(ctx.makeImage())
        var a = LayerAdjustment()
        a.gradientMap = [CodableColor(red: 0, green: 0, blue: 1, alpha: 1), CodableColor(red: 1, green: 1, blue: 0, alpha: 1)]
        let out = try #require(Renderer.adjusted(image, adjustment: a))
        let dark = Renderer.sample(out, at: CGPoint(x: 5, y: 5)), light = Renderer.sample(out, at: CGPoint(x: 30, y: 5))
        #expect(dark.blue > 0.9 && dark.red < 0.1)
        #expect(light.red > 0.9 && light.green > 0.9 && light.blue < 0.1)
        // The empty half stays empty.
        #expect(Renderer.sample(out, at: CGPoint(x: 5, y: 15)).alpha < 0.05)
    }

    @Test func oldFilesDecodeWithoutIt() throws {
        let a = try JSONDecoder().decode(LayerAdjustment.self, from: Data("{\"brightness\":0.1}".utf8))
        #expect(a.gradientMap == nil)
        var b = LayerAdjustment(); b.gradientMap = [.white, .white]
        let back = try JSONDecoder().decode(LayerAdjustment.self, from: try JSONEncoder().encode(b))
        #expect(back.gradientMap?.count == 2)
    }
}
