import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct RevealAllTests {
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 20); s.newLayer()
        var r = InkStroke(points: [InkPoint(x: 20, y: 5, pressure: 1), InkPoint(x: 30, y: 15, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1)
        r.kind = "rectangle"; r.filled = true
        s.layers[1].strokes = [r]
        return s
    }

    private func alpha(_ s: Studio, _ x: Int, _ y: Int) -> UInt8 {
        guard let img = Renderer.render(layers: [s.layers[1]], width: s.width, height: s.height), let b = PixelOps.bitmap(img) else { return 0 }
        return b.bytes[(y * s.width + x) * 4 + 3]
    }

    @Test func nothingSticksOutNothingChanges() {
        let s = studio()
        #expect(s.revealAllRect() == nil && !s.revealAll())
        #expect(s.width == 40 && s.height == 20)
    }

    @Test func grownCanvasKeepsTheMovedPart() {
        let s = studio()
        s.layers[1].transform.x = 25        // rectangle now spans 45…55, past the right edge
        #expect(s.revealAllRect() == CGRect(x: 0, y: 0, width: 55, height: 20))
        #expect(s.revealAll())
        #expect(s.width == 55 && s.height == 20)
        #expect(s.layers[1].transform == LayerTransform())
        #expect(alpha(s, 50, 10) > 200, "the part that was off the canvas is still there")
        #expect(alpha(s, 30, 10) == 0)
        s.undo()
        #expect(s.width == 40 && s.layers[1].transform.x == 25)
    }

    @Test func leftAndUpShiftEverything() {
        let s = studio()
        s.layers[1].transform.x = -30; s.layers[1].transform.y = -10   // −10…0 and −5…5
        #expect(s.revealAll())
        #expect(s.width == 50 && s.height == 25)
        #expect(alpha(s, 5, 5) > 200 && alpha(s, 45, 20) == 0)
    }

    @Test func canvasSizeNoLongerCutsMovedContent() {
        let s = studio()
        s.layers[1].transform.x = 25
        s.resizeCanvas(width: 60, height: 20, anchor: CGPoint(x: 0, y: 0))
        #expect(alpha(s, 50, 10) > 200)
    }
}
