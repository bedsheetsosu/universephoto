import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct TweenAllTests {
    /// Three key poses A, B, C on the active layer (x = 0, 40, 80).
    private func studioABC() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        s.addFrame(); s.layers[1].transform.x = 40; s.changed()
        s.addFrame(); s.layers[1].transform.x = 80; s.changed()
        s.selectFrame(0)
        return s
    }

    @Test func insertsBetweenEveryPairAndKeepsThePoses() {
        let s = studioABC()
        #expect(s.tweenAll(count: 2, curve: .linear) == 4)   // 2 pairs × 2 in-betweens
        let xs = s.document().frames.map { $0[1].transform.x }
        let want = [0.0, 40.0/3, 80.0/3, 40, 160.0/3, 200.0/3, 80]
        #expect(xs.count == want.count && zip(xs, want).allSatisfy { abs($0 - $1) < 1e-9 })
    }

    @Test func currentFrameStaysWithItsPose() {
        let s = studioABC()
        s.selectFrame(1)                                     // pose B, x = 40
        _ = s.tweenAll(count: 3, curve: .linear)
        #expect(s.layers[1].transform.x == 40)               // still on B after the inserts
    }

    @Test func onlyThePlayRangeIsTweened() {
        let s = studioABC()
        s.playRange = 0...1                                  // just A→B
        #expect(s.tweenAll(count: 2, curve: .linear) == 2)   // one pair only
        #expect(s.frames.count == 5)                         // 3 + 2
    }

    @Test func oneUndoStep() {
        let s = studioABC()
        let n = s.frames.count
        s.tweenAll(count: 2, curve: .smooth)
        s.undo()
        #expect(s.frames.count == n)
    }
}
