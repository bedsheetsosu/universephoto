import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FitDurationTests {
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        for k in 1..<n { s.addFrame(); s.layers[1].transform.x = Double(k); s.changed() }
        s.fps = 12
        s.selectFrame(0)
        return s
    }

    @Test func fitsToRoughlyTheTargetLength() {
        let s = frames(4)                                    // 4 frames, holds 1 → 4 ticks
        #expect(s.fitToDuration(seconds: 1) == true)         // target 12 ticks
        let ticks = (0..<s.frames.count).reduce(0) { $0 + s.hold($1) }
        #expect(abs(ticks - 12) <= 2)                        // ~12 at 12 fps
        #expect(s.frames.count == 4)                         // no frames added
    }

    @Test func neverBelowOnePerFrame() {
        let s = frames(10)                                   // 10 frames, 10 ticks
        s.fitToDuration(seconds: 0.1)                        // target 1 tick < frame count
        #expect((0..<s.frames.count).allSatisfy { s.hold($0) == 1 })
    }

    @Test func oneUndoStep() {
        let s = frames(4)
        s.fitToDuration(seconds: 3)
        s.undo()
        #expect((0..<s.frames.count).allSatisfy { s.hold($0) == 1 })
    }
}
