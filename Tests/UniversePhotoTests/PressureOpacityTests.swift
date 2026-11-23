import CoreGraphics
import Testing
@testable import UniversePhoto

struct PressureOpacityTests {
    func layer(pressureOpacity: Bool) -> ArtLayer {
        var s = InkStroke(points: [InkPoint(x: 50, y: 100, pressure: 1), InkPoint(x: 150, y: 100, pressure: 1), InkPoint(x: 250, y: 100, pressure: 0.25), InkPoint(x: 350, y: 100, pressure: 0.25)],
                          color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), width: 30)
        s.pressureOpacity = pressureOpacity ? true : nil
        var l = ArtLayer(name: "t"); l.strokes = [s]
        return l
    }

    @Test func lightPressureGivesLighterInk() throws {
        let image = try #require(Renderer.render(layers: [layer(pressureOpacity: true)], width: 400, height: 200))
        let hard = Renderer.sample(image, at: CGPoint(x: 100, y: 100)).alpha, soft = Renderer.sample(image, at: CGPoint(x: 310, y: 100)).alpha
        #expect(hard > 0.9)
        #expect(soft > 0.1 && soft < 0.45)
        // Above and below the line stays empty (the matte follows the stroke, not the canvas).
        #expect(Renderer.sample(image, at: CGPoint(x: 100, y: 160)).alpha < 0.05)
    }

    @Test func offKeepsFullInk() throws {
        let image = try #require(Renderer.render(layers: [layer(pressureOpacity: false)], width: 400, height: 200))
        #expect(Renderer.sample(image, at: CGPoint(x: 310, y: 100)).alpha > 0.9)
    }
}
