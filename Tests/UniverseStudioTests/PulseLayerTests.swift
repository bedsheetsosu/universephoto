import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct PulseLayerTests {
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 2, y: 2, pressure: 1)], color: .black, width: 2)]; s.changed()
        for _ in 1..<n { s.addFrame(); s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func fullAtEndsDipsInMiddleSeamless() {
        let n = 8, floor = 0.2
        let o = (0..<n).map { Studio.pulseOpacity(frameIndexInRange: $0, count: n, floor: floor) }
        #expect(abs(o[0] - 1) < 1e-9)                         // starts full
        #expect(abs(o[n / 2] - floor) < 1e-9)                 // dips to the floor at the middle
        #expect(o[1] == o[n - 1])                             // symmetric → loops without a jump
        #expect(o.allSatisfy { $0 >= floor - 1e-9 && $0 <= 1 + 1e-9 })
    }

    @Test func pulseWritesOpacityPerFrame() {
        let s = frames(8)
        #expect(s.pulseLayer(floor: 0.2) == 8)
        let ops = s.document().frames.map { $0[1].opacity }
        #expect(abs(ops[0] - 1) < 1e-9 && abs(ops[4] - 0.2) < 1e-9)
    }

    @Test func noneRestoresFullOpacity() {
        let s = frames(6)
        s.pulseLayer(floor: 0.1)
        #expect(s.unpulseLayer() == 6)
        #expect(s.document().frames.allSatisfy { abs($0[1].opacity - 1) < 1e-9 })
    }

    @Test func oneUndoStep() {
        let s = frames(6)
        s.pulseLayer(floor: 0.2)
        s.undo()
        #expect(s.document().frames.allSatisfy { abs($0[1].opacity - 1) < 1e-9 })
    }
}
