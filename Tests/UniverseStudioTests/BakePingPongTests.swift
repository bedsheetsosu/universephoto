import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct BakePingPongTests {
    private func studio(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 4, height: 4)
        for _ in 1..<n { s.addFrame() }
        for i in 0..<n { s.selectFrame(i); s.layers[0].name = "F\(i)" }
        s.selectFrame(0)
        return s
    }
    private func names(_ s: Studio) -> [String] { s.document().frames.map { $0[0].name } }

    @Test func allFramesOrTheRange() {
        let s = studio(4); s.pingPong = true; s.setHold(3, for: 2)
        #expect(s.bakePingPong() == 2)
        #expect(names(s) == ["F0", "F1", "F2", "F3", "F2", "F1"] && s.hold(4) == 3 && !s.pingPong)
        s.undo(); #expect(names(s) == ["F0", "F1", "F2", "F3"])
        s.playRange = 0...2
        #expect(s.bakePingPong() == 1)
        #expect(names(s) == ["F0", "F1", "F2", "F1", "F3"] && s.playRange == 0...3)
        #expect(studio(2).bakePingPong() == 0, "two frames already loop")
    }
}
