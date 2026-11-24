import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FrameSelectionTests {
    private func studio(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 4, height: 4)
        for _ in 1..<n { s.addFrame() }
        for i in 0..<n { s.selectFrame(i); s.layers[0].name = "F\(i)" }
        s.selectFrame(1)
        return s
    }
    private func names(_ s: Studio) -> [String] { s.document().frames.map { $0[0].name } }

    @Test func commandAndShiftClicks() {
        let s = studio(6)
        s.clickFrame(3, command: true, shift: false)
        #expect(s.framesForAction(at: 3) == [1, 3] && s.framesForAction(at: 5) == [5])
        s.clickFrame(3, command: true, shift: false)
        #expect(s.selectedFrames.isEmpty)
        s.clickFrame(4, command: false, shift: true)
        #expect(s.framesForAction(at: 2) == [1, 2, 3, 4])
    }

    @Test func groupDeleteHoldCopy() {
        let s = studio(6)
        s.clickFrame(4, command: false, shift: true)       // 1…4
        s.setHold(2, for: s.framesForAction(at: 2))
        #expect((0..<6).map { s.hold($0) } == [1, 2, 2, 2, 2, 1])
        s.copyFrames([3, 1])
        s.pasteFrame(after: 5)
        #expect(names(s) == ["F0", "F1", "F2", "F3", "F4", "F5", "F1", "F3"] && s.hold(6) == 2)
        s.removeFrames([1, 2, 3, 4])
        #expect(names(s) == ["F0", "F5", "F1", "F3"] && s.selectedFrames.isEmpty)
        s.undo(); #expect(s.document().frames.count == 8)
        #expect(s.framesForAction(at: 0) == [0])
        s.removeFrames(Array(0..<8))
        #expect(s.document().frames.count == 8, "at least one frame stays")
    }

    @Test func currentFrameFollowsDeletion() {
        let s = studio(5)
        s.selectFrame(3)
        s.removeFrames([0, 1])
        #expect(s.frameIndex == 1 && s.layers[0].name == "F3")
        s.removeFrames([1])
        #expect(s.frameIndex == 1 && s.layers[0].name == "F4")
    }
}
