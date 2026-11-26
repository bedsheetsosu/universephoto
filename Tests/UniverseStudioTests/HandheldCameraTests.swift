import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct HandheldCameraTests {
    @Test func everythingMovesTogether() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 30, y: 30, pressure: 1)], color: .black, width: 6)]
        s.layers[1].transform.x = 40; s.changed()
        for _ in 0..<23 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        let before = s.document().frames
        #expect(s.handheldCamera(amount: 6) > 0)
        let f = s.document().frames
        // The distance between two points on different layers stays the same: one camera move.
        for k in [5, 11, 17] {
            let a0 = CGPoint(x: 100, y: 100).applying(s.matrix(before[k][0].transform)), b0 = CGPoint(x: 30, y: 30).applying(s.matrix(before[k][1].transform))
            let a1 = CGPoint(x: 100, y: 100).applying(s.matrix(f[k][0].transform)), b1 = CGPoint(x: 30, y: 30).applying(s.matrix(f[k][1].transform))
            #expect(abs(hypot(a0.x - b0.x, a0.y - b0.y) - hypot(a1.x - b1.x, a1.y - b1.y)) < 0.01)
        }
        #expect(f[0][0].transform == before[0][0].transform)          // starts where it was
        s.undo()
        #expect(s.document().frames == before)
    }
}
