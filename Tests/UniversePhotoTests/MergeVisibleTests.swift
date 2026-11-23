import CoreGraphics
import Testing
@testable import UniversePhoto

@MainActor
struct MergeVisibleTests {
    func studio() -> Studio {
        let s = Studio()   // Background (white) + Sketch
        var r = InkStroke(points: [InkPoint(x: 100, y: 100, pressure: 1), InkPoint(x: 200, y: 200, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 2)
        r.kind = "rectangle"; r.filled = true
        s.add(r)
        s.newLayer(); s.mutateLayer("Hide") { $0.visible = false }
        return s
    }

    @Test func mergeVisibleKeepsHiddenLayers() throws {
        let s = studio()
        let n = s.layers.count
        s.mergeVisible()
        #expect(s.layers.count == n - 1 && s.layers.contains { !$0.visible })
        let merged = try #require(s.layers.first { $0.visible })
        let image = try #require(Renderer.render(layers: [merged], width: s.width, height: s.height))
        #expect(Renderer.sample(image, at: CGPoint(x: 150, y: 150)).red > 0.9)
        #expect(Renderer.sample(image, at: CGPoint(x: 500, y: 500)).green > 0.9)   // white background baked in
    }

    @Test func flattenAndStamp() {
        let s = studio()
        let n = s.layers.count
        s.stampVisible()
        #expect(s.layers.count == n + 1 && s.activeLayer?.imageData != nil)
        s.undo()
        #expect(s.layers.count == n)
        s.flattenImage()
        #expect(s.layers.count == 1 && s.layers[0].imageData != nil)
    }
}
