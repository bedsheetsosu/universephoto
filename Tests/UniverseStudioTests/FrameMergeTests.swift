import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FrameMergeTests {
    private func studioABB() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()      // frame 0 = A
        s.addFrame()                                   // frame 1 = copy of A (identical)
        s.addFrame(); s.layers[1].transform.x = 50; s.changed()  // frame 2 = B
        return s   // A, A, B
    }

    @Test func identicalNeighboursCollapseIntoAHold() {
        let s = studioABB()
        #expect(s.frames.count == 3)
        #expect(s.mergeIdenticalFrames() == 1)         // the duplicate A is removed
        #expect(s.frames.count == 2)
        #expect(s.hold(0) == 2)                        // its hold moved onto the kept A
        #expect(s.hold(1) == 1)
    }

    @Test func totalLengthIsKept() {
        let s = studioABB()
        let before = (0..<s.frames.count).reduce(0) { $0 + s.hold($1) }
        s.mergeIdenticalFrames()
        let after = (0..<s.frames.count).reduce(0) { $0 + s.hold($1) }
        #expect(before == after)
    }

    @Test func nothingToMergeReturnsZeroNoUndo() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white); s.addFrame(); s.layers[1].transform.x = 9; s.changed()
        let undo = s.undoStack.count
        #expect(s.mergeIdenticalFrames() == 0)         // the two frames differ
        #expect(s.undoStack.count == undo)             // no checkpoint spent
    }

    @Test func runsNeverExceedTheHoldCap() {
        // 120 identical frames can't become a single hold of 120 (cap 99) – length stays exact.
        var frames = Array(repeating: [ArtLayer(name: "a")], count: 120)
        frames.append([ArtLayer(name: "b")])
        let holds = Array(repeating: 1, count: 121)
        let plan = Studio.mergeRuns(frames, holds: holds, in: 0...120)
        #expect(plan.newHolds.values.allSatisfy { $0 <= 99 })      // never past the per-frame cap
        // Total on-screen length is preserved exactly across the kept frames.
        let removed = Set(plan.remove)
        let total = (0...120).filter { !removed.contains($0) }.reduce(0) { $0 + (plan.newHolds[$1] ?? holds[$1]) }
        #expect(total == 121)
    }
}
