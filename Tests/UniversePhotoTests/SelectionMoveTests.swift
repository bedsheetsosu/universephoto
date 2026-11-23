import CoreGraphics
import Testing
@testable import UniversePhoto

@MainActor
struct SelectionMoveTests {
    @Test func shapesMoveTheirPoints() {
        let s = Studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40)], ellipse: true)
        #expect(s.selectionContains(CGPoint(x: 30, y: 25)) && !s.selectionContains(CGPoint(x: 100, y: 100)))
        s.nudgeSelection(dx: 10, dy: -5)
        #expect(s.selection?.points == [CGPoint(x: 20, y: 5), CGPoint(x: 60, y: 35)] && s.selection?.ellipse == true)
    }

    @Test func pixelMasksShiftDownAndRight() throws {
        let s = Studio()
        var m = [UInt8](repeating: 0, count: s.width * s.height)
        for y in 100..<120 { for x in 200..<230 { m[y * s.width + x] = 255 } }
        s.setSelection(mask: m)
        let moved = try #require(s.movedSelection(s.selection!, by: CGPoint(x: 50, y: 30)))
        s.selection = moved
        let mask = try #require(s.selectionMask())
        #expect(mask[140 * s.width + 260] == 255)   // old (210, 110) + (50, 30)
        #expect(mask[110 * s.width + 210] == 0)
        #expect(s.selection?.bounds.minX == 250 && s.selection?.bounds.minY == 130)
    }
}
