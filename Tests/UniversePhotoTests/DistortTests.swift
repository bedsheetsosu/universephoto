import CoreGraphics
import Testing
@testable import UniversePhoto

@MainActor
struct DistortTests {
    func studioWithSquare() -> Studio {
        let s = Studio()
        s.newLayer()
        var r = InkStroke(points: [InkPoint(x: 100, y: 100, pressure: 1), InkPoint(x: 300, y: 300, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 2)
        r.kind = "rectangle"; r.filled = true
        s.add(r)
        return s
    }

    @Test func cornersStartOnTheContentAndApplyWarps() throws {
        let s = studioWithSquare()
        s.beginDistort()
        let c = try #require(s.distortCorners)
        #expect(c.count == 4 && abs(c[0].x - 100) <= 2 && abs(c[2].y - 300) <= 2)
        // Pull the bottom-right corner far out: the red reaches there after applying.
        s.moveDistortCorner(2, to: CGPoint(x: 600, y: 500))
        s.applyDistort()
        #expect(!s.distorting)
        let layer = try #require(s.activeLayer)
        #expect(layer.imageData != nil && layer.strokes.isEmpty)
        let image = try #require(Renderer.render(layers: [layer], width: s.width, height: s.height))
        #expect(Renderer.sample(image, at: CGPoint(x: 500, y: 420)).red > 0.8)
        #expect(Renderer.sample(image, at: CGPoint(x: 150, y: 450)).alpha < 0.1)
    }

    @Test func cancelLeavesTheLayerAlone() throws {
        let s = studioWithSquare()
        let before = s.activeLayer
        s.beginDistort()
        s.moveDistortCorner(0, to: CGPoint(x: 0, y: 0))
        s.cancelDistort()
        #expect(s.activeLayer == before && !s.distorting)
    }
}
