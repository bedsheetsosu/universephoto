import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ThinFramesTests {
    /// `n` distinct frames, all on ones (hold 1).
    private func onOnes(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        for k in 1..<n { s.addFrame(); s.layers[1].transform.x = Double(k) * 7; s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func onTwosHalvesFramesAndDoublesHolds() {
        let s = onOnes(4)                                    // frames 0,1,2,3
        #expect(s.thinFrames(every: 2) == 2)                 // drops 1 and 3
        #expect(s.frames.count == 2)
        #expect(s.hold(0) == 2 && s.hold(1) == 2)            // each kept drawing holds for 2
    }

    @Test func totalLengthIsKept() {
        let s = onOnes(5)
        let before = (0..<s.frames.count).reduce(0) { $0 + s.hold($1) }
        s.thinFrames(every: 3)
        let after = (0..<s.frames.count).reduce(0) { $0 + s.hold($1) }
        #expect(before == after)                             // 5 ticks either way
    }

    @Test func planRemovesTheRightIndices() {
        let plan = Studio.thinPlan(holds: Array(repeating: 1, count: 6), in: 0...5, step: 2)
        #expect(plan.remove.sorted() == [1, 3, 5])
        #expect(plan.newHolds == [0: 2, 2: 2, 4: 2])
    }

    @Test func oneUndoStep() {
        let s = onOnes(4)
        s.thinFrames(every: 2)
        s.undo()
        #expect(s.frames.count == 4)
    }
}
