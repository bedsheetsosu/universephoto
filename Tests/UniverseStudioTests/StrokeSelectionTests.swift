import CoreGraphics
import Testing
@testable import UniverseStudio

@MainActor
struct StrokeSelectionTests {
    func square(_ w: Int, _ h: Int) -> [UInt8] {
        (0..<(w * h)).map { i in let x = i % w, y = i / w; return (20..<60).contains(x) && (20..<60).contains(y) ? 255 : 0 }
    }

    @Test func bandSitsWhereAsked() throws {
        let m = square(80, 80)
        let inside = try #require(Studio.strokeBand(m, width: 80, height: 80, lineWidth: 4, position: .inside))
        let outside = try #require(Studio.strokeBand(m, width: 80, height: 80, lineWidth: 4, position: .outside))
        func at(_ b: [UInt8], _ x: Int, _ y: Int) -> UInt8 { b[y * 80 + x] }
        #expect(at(inside, 21, 40) > 128 && at(inside, 40, 40) == 0 && at(inside, 17, 40) == 0)
        #expect(at(outside, 17, 40) > 128 && at(outside, 21, 40) == 0 && at(outside, 5, 40) == 0)
    }

    @Test func fillAndStrokeLandOnTheLayer() throws {
        let s = Studio()
        s.color = CodableColor(red: 0, green: 0, blue: 1, alpha: 1); s.brushOpacity = 1
        s.selection = CanvasSelection(points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)])
        let before = s.activeLayer?.strokes.count ?? 0
        s.fillSelection()
        s.strokeSelection(width: 6, position: .outside)
        let layer = try #require(s.activeLayer)
        #expect(layer.strokes.count == before + 2)
        var plain = layer; plain.strokes = [layer.strokes[layer.strokes.count - 2]]
        let image = try #require(Renderer.render(layers: [plain], width: s.width, height: s.height))
        #expect(Renderer.sample(image, at: CGPoint(x: 150, y: 150)).blue > 0.9)
        #expect(Renderer.sample(image, at: CGPoint(x: 250, y: 150)).alpha < 0.1)
    }
}
