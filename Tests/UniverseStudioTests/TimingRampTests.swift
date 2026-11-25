import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct TimingRampTests {
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        for k in 1..<n { s.addFrame(); s.layers[1].transform.x = Double(k); s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func slowStartHoldsTheFirstFramesLongest() {
        let s = frames(4)
        #expect(s.rampTiming(slowStart: true, extra: 3))
        #expect((0..<4).map { s.hold($0) } == [4, 3, 2, 1])
        #expect(s.frames.count == 4)
    }

    @Test func slowEndHoldsTheLastFramesLongest() {
        let s = frames(4)
        s.rampTiming(slowStart: false, extra: 3)
        #expect((0..<4).map { s.hold($0) } == [1, 2, 3, 4])
    }

    @Test func resetPutsEveryFrameBackOnOnes() {
        let s = frames(4)
        s.rampTiming(slowStart: true, extra: 3)
        #expect(s.resetTiming())
        #expect((0..<4).allSatisfy { s.hold($0) == 1 })
        #expect(!s.resetTiming())                       // nothing left to reset, no extra undo step
    }

    @Test func oneUndoStep() {
        let s = frames(4)
        s.rampTiming(slowStart: true)
        s.undo()
        #expect((0..<4).allSatisfy { s.hold($0) == 1 })
    }
}
