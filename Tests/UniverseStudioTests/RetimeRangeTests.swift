import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RetimeRangeTests {
    private func threeFrames() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        s.addFrame(); s.layers[1].transform.x = 10; s.changed()
        s.addFrame(); s.layers[1].transform.x = 20; s.changed()
        s.selectFrame(0)
        return s
    }

    @Test func slowMotionDoublesHoldsNoFramesAdded() {
        let s = threeFrames()
        #expect(s.retimeRange(factor: 2) == true)
        #expect(s.frames.count == 3)                          // nothing added or removed
        #expect((0..<3).map { s.hold($0) } == [2, 2, 2])
    }

    @Test func fastForwardHalvesButNeverBelowOne() {
        let holds = [1, 2, 4]
        let out = Studio.retimedHolds(holds, in: 0...2, factor: 0.5)
        #expect(out == [1, 1, 2])                             // 1→1 (min), 2→1, 4→2
    }

    @Test func holdsClampAt99() {
        let out = Studio.retimedHolds([80], in: 0...0, factor: 3)
        #expect(out == [99])
    }

    @Test func oneUndoStep() {
        let s = threeFrames()
        s.retimeRange(factor: 3)
        s.undo()
        #expect((0..<3).map { s.hold($0) } == [1, 1, 1])
    }
}
