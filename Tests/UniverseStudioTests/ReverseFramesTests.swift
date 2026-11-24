import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ReverseFramesTests {
    private func studio(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 4, height: 4)
        for _ in 1..<n { s.addFrame() }
        for i in 0..<n { s.selectFrame(i); s.layers[0].name = "F\(i)" }
        return s
    }
    private func names(_ s: Studio) -> [String] { s.document().frames.map { $0[0].name } }

    @Test func reversesAllOrTheRange() {
        let s = studio(4); s.selectFrame(1); s.setHold(3, for: 0)
        s.reverseFrames()
        #expect(names(s) == ["F3", "F2", "F1", "F0"] && s.frameHolds == [1, 1, 1, 3])
        #expect(s.frameIndex == 2 && s.layers[0].name == "F1")
        s.undo(); #expect(names(s) == ["F0", "F1", "F2", "F3"])
        s.playRange = 1...2
        s.reverseFrames()
        #expect(names(s) == ["F0", "F2", "F1", "F3"])
    }

    @Test func firstAndLastRespectTheRange() {
        let s = studio(5)
        s.firstFrame(); #expect(s.frameIndex == 0)
        s.lastFrame(); #expect(s.frameIndex == 4)
        s.playRange = 1...3
        s.firstFrame(); #expect(s.frameIndex == 1)
        s.lastFrame(); #expect(s.frameIndex == 3)
    }
}
