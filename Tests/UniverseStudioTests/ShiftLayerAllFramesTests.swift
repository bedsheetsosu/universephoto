import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ShiftLayerAllFramesTests {
    private func moving() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        s.addFrame(); s.layers[1].transform.x = 30; s.changed()
        s.addFrame(); s.layers[1].transform.x = 60; s.changed()
        s.selectFrame(1)
        return s
    }

    @Test func keepsTheMotionAndAddsTheOffset() {
        let s = moving()
        #expect(s.shiftLayerAllFrames(dx: 10, dy: -5) == 3)
        let f = s.document().frames
        #expect(f.map { $0[1].transform.x } == [10, 40, 70])
        #expect(f.allSatisfy { $0[1].transform.y == -5 })
        #expect(f.allSatisfy { $0[0].transform.x == 0 })   // other layers untouched
    }

    @Test func oneUndoStep() {
        let s = moving()
        s.shiftLayerAllFrames(dx: 10, dy: 0)
        s.undo()
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 30, 60])
    }
}
