import CoreGraphics
import Testing
@testable import UniverseStudio

struct EraserPressureTests {
    @Test func lightPressureErasesPartly() throws {
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), width: 1)
        fill.kind = "fill"
        var erase = InkStroke(points: [InkPoint(x: 50, y: 100, pressure: 0.3), InkPoint(x: 350, y: 100, pressure: 0.3)], color: .white, width: 30, isEraser: true)
        erase.pressureOpacity = true
        var l = ArtLayer(name: "t"); l.strokes = [fill, erase]
        let image = try #require(Renderer.render(layers: [l], width: 400, height: 200))
        let a = Renderer.sample(image, at: CGPoint(x: 200, y: 100)).alpha
        #expect(a > 0.5 && a < 0.85)
        #expect(Renderer.sample(image, at: CGPoint(x: 200, y: 160)).alpha > 0.99)
    }
}
