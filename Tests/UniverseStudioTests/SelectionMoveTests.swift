import CoreGraphics
import Testing
@testable import UniverseStudio

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

@MainActor
struct SelectionTransformTests {
    @Test func frameScalesShapesAndCancelRestores() {
        let s = Studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 150)])
        s.beginSelectionTransform()
        #expect(s.selectionFrame == CGRect(x: 100, y: 100, width: 100, height: 50))
        // Drag the right edge out to 300: twice as wide.
        let grab = Studio.frameGrab(s.selectionFrame, at: CGPoint(x: 200, y: 125), tolerance: 5)
        s.updateSelectionFrame(Studio.frameDrag(grab, to: CGPoint(x: 300, y: 125)))
        #expect(s.selection?.bounds == CGRect(x: 100, y: 100, width: 200, height: 50))
        s.cancelSelectionTransform()
        #expect(s.selection?.bounds == CGRect(x: 100, y: 100, width: 100, height: 50) && !s.transformingSelection)
    }

    @Test func pixelMasksScaleToo() throws {
        let s = Studio()
        var m = [UInt8](repeating: 0, count: s.width * s.height)
        for y in 100..<120 { for x in 100..<140 { m[y * s.width + x] = 255 } }
        s.setSelection(mask: m)
        s.beginSelectionTransform()
        s.updateSelectionFrame(CGRect(x: 100, y: 100, width: 80, height: 40))
        s.applySelectionTransform()
        let mask = try #require(s.selectionMask())
        #expect(mask[135 * s.width + 170] > 200)   // inside the doubled box
        #expect(mask[150 * s.width + 190] == 0)
        #expect(!s.transformingSelection)
    }

    @Test func rotatingTurnsRectangleIntoOutline() {
        let s = Studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 140)])
        s.beginSelectionTransform()
        s.rotateSelectionFrame(to: 90)
        let b = s.selection!.bounds
        // 100 × 40 turned by 90° around (150, 120): 40 wide, 100 tall, same centre.
        #expect(abs(b.width - 40) < 0.01 && abs(b.height - 100) < 0.01)
        #expect(abs(b.midX - 150) < 0.01 && abs(b.midY - 120) < 0.01)
        #expect(s.selection!.points.count == 4 && !s.selection!.ellipse)
        s.rotateSelectionFrame(to: 37, snap: true)
        #expect(s.selectionAngle == 30)
        s.rotateSelectionFrame(to: 270)
        #expect(s.selectionAngle == -90)
        s.cancelSelectionTransform()
        #expect(s.selection!.points.count == 2 && s.selectionAngle == 0)
    }

    @Test func dragsWorkInFrameSpaceWhenTurned() {
        let s = Studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 140)])
        s.beginSelectionTransform()
        s.rotateSelectionFrame(to: 90)
        // On the canvas the frame's right edge (x = 200) now sits at y = 170.
        let canvasPoint = CGPoint(x: 150, y: 170)
        #expect(s.selectionRotateZone(CGPoint(x: 150, y: 190), tolerance: 8))
        #expect(!s.selectionRotateZone(canvasPoint, tolerance: 8))
        let grab = Studio.frameGrab(s.selectionFrame, at: s.frameSpace(canvasPoint), tolerance: 5)
        s.updateSelectionFrame(Studio.frameDrag(grab, to: s.frameSpace(CGPoint(x: 150, y: 220))))
        let b = s.selection!.bounds
        #expect(abs(b.minY - 70) < 0.01 && abs(b.maxY - 220) < 0.01, "opposite edge stays")
    }

    @Test func turningAfterAMoveKeepsThePlace() {
        let s = Studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 140)])
        s.beginSelectionTransform()
        s.rotateSelectionFrame(to: 90)
        s.updateSelectionFrame(s.selectionFrame!.offsetBy(dx: 50, dy: 0))
        let before = s.selection!.bounds
        s.beginSelectionRotation()
        s.rotateSelectionFrame(to: 90)
        let after = s.selection!.bounds
        #expect(abs(before.midX - after.midX) < 0.01 && abs(before.midY - after.midY) < 0.01)
        #expect(abs(before.width - after.width) < 0.01)
    }

    @Test func pixelMasksRotate() throws {
        let s = Studio()
        var m = [UInt8](repeating: 0, count: s.width * s.height)
        for y in 100..<120 { for x in 100..<180 { m[y * s.width + x] = 255 } }
        s.setSelection(mask: m)
        s.beginSelectionTransform()
        s.rotateSelectionFrame(to: 90)
        let mask = try #require(s.selectionMask())
        // 80 × 20 around (140, 110) becomes 20 × 80.
        #expect(mask[140 * s.width + 140] > 200)
        #expect(mask[110 * s.width + 170] == 0)
    }
}
