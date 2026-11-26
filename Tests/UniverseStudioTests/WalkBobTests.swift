import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct WalkBobTests {
    @Test func liftsEachStepAndTipsBothWays() {
        let b = (0..<16).map { Studio.walkBob(frame: $0, of: 16, steps: 4, height: 10, tilt: 5) }
        #expect(b[0].lift == 0 && b[4].lift < 1e-9)              // feet down between steps
        #expect(abs(b[2].lift - 10) < 1e-9 && abs(b[6].lift - 10) < 1e-9)
        #expect(b[2].tilt > 0 && b[6].tilt < 0)                  // other foot, other side
    }

    @Test func movesTheLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 40, y: 40, pressure: 1), InkPoint(x: 60, y: 80, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<7 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.walkBob(steps: 2, height: 6, tilt: 4) > 0)
        let f = s.document().frames
        #expect(f[2][1].transform.y < 0 && f[2][1].transform.rotation > 0)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform == LayerTransform() })
    }
}
