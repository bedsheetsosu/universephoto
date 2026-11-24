import CoreGraphics
import Testing
@testable import UniverseStudio

@MainActor
struct RawPixelsTests {
    @Test func rawPixelsLeaveLayerEffectsOut() throws {
        let s = Studio()
        s.newLayer()
        var r = InkStroke(points: [InkPoint(x: 100, y: 100, pressure: 1), InkPoint(x: 200, y: 200, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 2)
        r.kind = "rectangle"; r.filled = true
        s.add(r)
        var style = LayerStyle(); style.outline.on = true; style.outline.width = 10
        s.mutateLayer("Style") { $0.style = style }
        // The outline would sit just outside the rectangle; the raw pixels must not have it.
        let raw = try #require(s.rawLayerPixels())
        #expect(Renderer.sample(raw, at: CGPoint(x: 205, y: 150)).alpha < 0.1)
        #expect(Renderer.sample(raw, at: CGPoint(x: 150, y: 150)).red > 0.9)
        // …while the layer as shown does.
        let shown = try #require(Renderer.render(layers: [s.activeLayer!], width: s.width, height: s.height))
        #expect(Renderer.sample(shown, at: CGPoint(x: 205, y: 150)).alpha > 0.5)
    }
}
