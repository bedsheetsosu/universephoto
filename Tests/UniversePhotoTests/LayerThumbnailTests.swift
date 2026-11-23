import CoreGraphics
import Testing
@testable import UniversePhoto

@MainActor
struct LayerThumbnailTests {
    @Test func thumbnailIsSmallAndShowsTheContent() throws {
        var layer = ArtLayer(name: "t")
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1), width: 1)
        fill.kind = "fill"
        layer.strokes = [fill]
        let image = try #require(LayerThumbnail.render(layer, width: 1200, height: 800))
        #expect(image.width == 96 && image.height == 64)
        #expect(Renderer.sample(image, at: CGPoint(x: 48, y: 32)).blue > 0.9)
    }

    @Test func keyFollowsChanges() {
        var layer = ArtLayer(name: "t")
        let a = LayerThumbnail.key(layer, width: 100, height: 100)
        layer.strokes.append(InkStroke(points: [InkPoint(x: 1, y: 1, pressure: 1)], color: .white, width: 2))
        let b = LayerThumbnail.key(layer, width: 100, height: 100)
        layer.transform.x = 5
        let c = LayerThumbnail.key(layer, width: 100, height: 100)
        #expect(a != b && b != c)
    }
}
