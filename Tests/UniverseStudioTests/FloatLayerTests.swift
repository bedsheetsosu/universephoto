import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FloatLayerTests {
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 20, height: 20, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 5, y: 5, pressure: 1)], color: .black, width: 2)]
        s.layers[1].transform = LayerTransform(); s.changed()
        for _ in 1..<n { s.addFrame(); s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func offsetIsASineThatReturnsToZero() {
        let n = 8, amp = 10.0
        let o = (0..<n).map { Studio.floatOffset(frameIndexInRange: $0, count: n, amplitude: amp) }
        #expect(abs(o[0]) < 1e-9)                              // starts at zero
        #expect(abs(o[2] - amp) < 1e-9)                        // peak up at a quarter
        #expect(abs(o[6] + amp) < 1e-9)                        // peak down at three quarters
        #expect(abs(o[4]) < 1e-9)                              // back through zero at the middle
    }

    @Test func driftMovesTheLayerVerticallyPerFrame() {
        let s = frames(8)
        #expect(s.floatLayer(amplitude: 10, horizontal: false) == 8)
        let ys = s.document().frames.map { $0[1].transform.y }
        #expect(abs(ys[0]) < 1e-9 && ys[2] > 5 && ys[6] < -5)  // bobs up then down
        #expect(s.document().frames.allSatisfy { $0[1].transform.x == 0 })  // x untouched
    }

    @Test func oneUndoStep() {
        let s = frames(6)
        s.floatLayer(amplitude: 20, horizontal: true)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.x == 0 && $0[1].transform.y == 0 })
    }
}
