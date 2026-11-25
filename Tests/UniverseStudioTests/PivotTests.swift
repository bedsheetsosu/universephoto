import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct PivotTests {
    private func offCentre() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 300, height: 200, background: .white)
        var ball = InkStroke(points: [InkPoint(x: 20, y: 150, pressure: 1), InkPoint(x: 60, y: 190, pressure: 1)], color: .black, width: 1)
        ball.kind = "ellipse"; ball.filled = true
        s.layers[1].strokes = [ball]; s.changed()
        for _ in 0..<3 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        return s
    }

    private func screenPoint(_ s: Studio, frame: Int, _ p: Studio.Pivot) -> CGPoint {
        let l = s.document().frames[frame][1]
        return s.pivotPoint(l, p)!.applying(s.matrix(l.transform))
    }

    @Test func spinTurnsAroundTheDrawing() {
        let s = offCentre()
        let before = screenPoint(s, frame: 2, .centre)
        s.spinLayerOverFrames(turns: 1)
        let after = screenPoint(s, frame: 2, .centre)
        #expect(abs(before.x - after.x) < 1e-6 && abs(before.y - after.y) < 1e-6)
    }

    @Test func stretchKeepsTheFeetOnTheGround() {
        let s = offCentre()
        let before = screenPoint(s, frame: 1, .bottom)
        s.stretchEffect(jelly: false, amount: 0.2)
        let l = s.document().frames[1][1]
        #expect((l.transform.stretch ?? 1) > 1)
        let after = screenPoint(s, frame: 1, .bottom)
        #expect(abs(before.x - after.x) < 1e-6 && abs(before.y - after.y) < 1e-6)
    }
}
