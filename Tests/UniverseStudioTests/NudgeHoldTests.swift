import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct NudgeHoldTests {
    @Test func longerShorterAndSelection() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 4, height: 4); s.addFrame(); s.addFrame(); s.selectFrame(0)
        s.nudgeHold(1); s.nudgeHold(1)
        #expect(s.hold(0) == 3)
        s.nudgeHold(-5)
        #expect(s.hold(0) == 1 && s.frameHolds.isEmpty)
        s.clickFrame(2, command: true, shift: false)
        s.nudgeHold(1)
        #expect(s.frameHolds == [2, 1, 2])
        s.undo(); #expect(s.frameHolds.isEmpty)
    }
}
