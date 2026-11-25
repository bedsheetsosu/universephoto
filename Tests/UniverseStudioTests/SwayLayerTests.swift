import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SwayLayerTests {
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 20, height: 20, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 5, y: 5, pressure: 1)], color: .black, width: 2)]
        s.layers[1].transform = LayerTransform(); s.changed()
        for _ in 1..<n { s.addFrame(); s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func rotationSwingsAndReturns() {
        let n = 8, deg = 10.0
        let o = (0..<n).map { Studio.swayDegrees(frameIndexInRange: $0, count: n, degrees: deg) }
        #expect(abs(o[0]) < 1e-9 && abs(o[4]) < 1e-9)          // zero at start and middle
        #expect(abs(o[2] - deg) < 1e-9 && abs(o[6] + deg) < 1e-9)  // peaks each way
    }

    @Test func rotatesTheLayerPerFrame() {
        let s = frames(8)
        #expect(s.swayLayer(degrees: 10) == 8)
        let rot = s.document().frames.map { $0[1].transform.rotation }
        #expect(abs(rot[0]) < 1e-9 && rot[2] > 5 && rot[6] < -5)
    }

    @Test func oneUndoStep() {
        let s = frames(6)
        s.swayLayer(degrees: 12)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.rotation == 0 })
    }
}
