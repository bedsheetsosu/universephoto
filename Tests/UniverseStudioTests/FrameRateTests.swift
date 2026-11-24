import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FrameRateTests {
    @Test func retimingKeepsLength() {
        #expect(Studio.retimed([1, 2, 3], from: 12, to: 24) == [2, 4, 6])
        #expect(Studio.retimed([2, 3, 1], from: 24, to: 12) == [1, 2, 1])
    }

    @Test func changeWithAndWithoutTiming() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 4, height: 4); s.addFrame(); s.addFrame()
        s.fps = 12; s.setHold(2, for: 1)
        let before = s.animationDuration
        s.changeFPS(24, keepTiming: true)
        #expect(s.fps == 24 && s.frameHolds == [2, 4, 2] && abs(s.animationDuration - before) < 1e-9)
        s.changeFPS(500, keepTiming: false)
        #expect(s.fps == 120 && s.frameHolds == [2, 4, 2])
        s.undo(); #expect(s.fps == 24)
        s.undo(); #expect(s.fps == 12 && s.frameHolds == [1, 2, 1])
    }
}
