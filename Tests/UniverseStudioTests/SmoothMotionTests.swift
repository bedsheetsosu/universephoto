import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SmoothMotionTests {
    @Test func averagesNeighboursAndKeepsTheEnds() {
        #expect(Studio.smoothed([0, 40, 0, 40, 0], passes: 1, loop: false) == [0, 20, 20, 20, 0])
        #expect(Studio.smoothed([0, 40, 0, 40], passes: 1, loop: true) == [20, 20, 20, 20])
    }

    @Test func smoothsTheLayerInOneUndoStep() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for (k, x) in [0.0, 40, 0, 40, 0].enumerated() {
            if k > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        #expect(s.smoothMotion(passes: 1) == 3)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 20, 20, 20, 0])
        s.undo()
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 40, 0, 40, 0])
    }
}
