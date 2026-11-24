import CoreGraphics
import Testing
@testable import UniverseStudio

@MainActor
struct CropToolTests {
    @Test func drawAdjustMoveAndApply() {
        let s = Studio()
        let w = s.width, h = s.height
        s.cropDrag(s.cropPress(at: CGPoint(x: 100, y: 100), tolerance: 6), to: CGPoint(x: 300, y: 250))
        #expect(s.cropRect == CGRect(x: 100, y: 100, width: 200, height: 150))
        // The right edge widens it, a press inside moves it, never off the canvas.
        let edge = s.cropPress(at: CGPoint(x: 301, y: 180), tolerance: 6)
        s.cropDrag(edge, to: CGPoint(x: 350, y: 180))
        #expect(s.cropRect == CGRect(x: 100, y: 100, width: 250, height: 150))
        let move = s.cropPress(at: CGPoint(x: 200, y: 150), tolerance: 6)
        s.cropDrag(move, to: CGPoint(x: -1000, y: 150))
        #expect(s.cropRect?.minX == 0 && s.cropRect?.width == 250)
        s.applyCrop()
        #expect(s.width == 250 && s.height == 150 && s.cropRect == nil)
        #expect(w != s.width || h != s.height)
    }

    @Test func shiftMakesASquareAndCanvasClamps() {
        let s = Studio()
        s.cropDrag(.new(CGPoint(x: 10, y: 10)), to: CGPoint(x: 110, y: 50), square: true)
        #expect(s.cropRect?.width == 100 && s.cropRect?.height == 100)
        s.cropDrag(.new(CGPoint(x: 10, y: 10)), to: CGPoint(x: -50, y: -50))
        #expect(s.cropRect == CGRect(x: 0, y: 0, width: 10, height: 10))
    }
}
