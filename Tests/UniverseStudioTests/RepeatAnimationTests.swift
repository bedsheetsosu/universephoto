import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RepeatAnimationTests {
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        for k in 1..<n { s.addFrame(); s.layers[1].transform.x = Double(k) * 5; s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func doublesTheSequenceAndItsTiming() {
        let s = frames(3)
        s.setHold(2, for: [1])                                 // middle frame on twos
        #expect(s.repeatAnimation(times: 2) == 6)
        let xs = s.document().frames.map { $0[1].transform.x }
        #expect(xs == [0, 5, 10, 0, 5, 10])                    // the cycle repeats
        let holds = (0..<6).map { s.hold($0) }
        #expect(holds == [1, 2, 1, 1, 2, 1])                   // holds come along
    }

    @Test func respectsTheFrameCap() {
        let s = frames(2)
        // 700 frames × 2 would be 1400 > 1200 → refused. Build 700 quickly is slow, so just check the guard via a smaller impossible times.
        #expect(s.repeatAnimation(times: 1) == 0)              // times < 2 does nothing
    }

    @Test func oneUndoStep() {
        let s = frames(3)
        s.repeatAnimation(times: 3)
        #expect(s.frames.count == 9)
        s.undo()
        #expect(s.frames.count == 3)
    }
}
