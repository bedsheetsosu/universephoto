import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct GradientStopTests {
    private let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1), green = CodableColor(red: 0, green: 1, blue: 0, alpha: 1), blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)

    private func render(kind: String, stops: [GradientStop]?) -> CGImage? {
        var g = InkStroke(points: [InkPoint(x: 0, y: 5, pressure: 1), InkPoint(x: 100, y: 5, pressure: 1)], color: red, width: 1)
        g.kind = kind; g.secondaryColor = blue; g.gradientStops = stops
        var layer = ArtLayer(name: "G"); layer.strokes = [g]
        return Renderer.render(layers: [layer], width: 100, height: 10)
    }

    @Test func threeStopsPassThroughTheMiddleColour() throws {
        let img = try #require(render(kind: "gradient", stops: [GradientStop(color: red, location: 0), GradientStop(color: blue, location: 1), GradientStop(color: green, location: 0.5)]))
        let mid = Renderer.sample(img, at: CGPoint(x: 50, y: 5))
        #expect(mid.green > 0.9 && mid.red < 0.1 && mid.blue < 0.1)
        #expect(Renderer.sample(img, at: CGPoint(x: 99, y: 5)).blue > 0.9)
    }

    @Test func withoutStopsItIsStillTwoColours() throws {
        let img = try #require(render(kind: "gradient", stops: nil))
        let mid = Renderer.sample(img, at: CGPoint(x: 50, y: 5))
        #expect(mid.red > 0.4 && mid.blue > 0.4 && mid.green < 0.05)
    }

    @Test func reflectedMirrorsTheStops() throws {
        // Drag from x 0 to 100: the start colour at 0, the end colour at both ±100.
        var g = InkStroke(points: [InkPoint(x: 50, y: 5, pressure: 1), InkPoint(x: 100, y: 5, pressure: 1)], color: red, width: 1)
        g.kind = "gradientReflected"; g.gradientStops = [GradientStop(color: red, location: 0), GradientStop(color: green, location: 0.5), GradientStop(color: blue, location: 1)]
        var layer = ArtLayer(name: "G"); layer.strokes = [g]
        let img = try #require(Renderer.render(layers: [layer], width: 100, height: 10))
        #expect(Renderer.sample(img, at: CGPoint(x: 50, y: 5)).red > 0.9)
        #expect(Renderer.sample(img, at: CGPoint(x: 25, y: 5)).green > 0.9 && Renderer.sample(img, at: CGPoint(x: 75, y: 5)).green > 0.9)
    }

    @Test func editingStops() {
        let s = Studio(); s.gradientStops = nil
        s.color = red; s.secondaryColor = blue
        #expect(s.effectiveGradientStops.count == 2)
        s.color = green
        let i = s.addGradientStop(at: 0.5)
        #expect(s.gradientStops?.count == 3 && s.gradientStops?[i].color == green && i == 1)
        s.moveGradientStop(i, to: 1.4)
        #expect(s.gradientStops?[i].location == 1)
        s.removeGradientStop(0); s.removeGradientStop(0)
        #expect(s.gradientStops?.count == 2, "never fewer than two")
        s.gradientStops = nil
    }
}
