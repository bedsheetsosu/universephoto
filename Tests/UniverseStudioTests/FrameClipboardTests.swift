import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FrameClipboardTests {
    private func studio(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 4, height: 4)
        for _ in 1..<n { s.addFrame() }
        for i in 0..<n { s.selectFrame(i); s.layers[0].name = "F\(i)" }
        return s
    }
    private func names(_ s: Studio) -> [String] { s.document().frames.map { $0[0].name } }

    @Test func copyPasteWithHold() {
        let s = studio(3); s.setHold(2, for: 0)
        #expect(!s.pasteFrame(after: 0), "nothing copied yet")
        s.copyFrame(0)
        #expect(s.pasteFrame(after: 2))
        #expect(names(s) == ["F0", "F1", "F2", "F0"] && s.hold(3) == 2 && s.frameIndex == 3)
        s.undo(); #expect(names(s) == ["F0", "F1", "F2"])
    }

    @Test func referenceStaysOnItsDrawing() {
        let s = studio(4)
        s.toggleReference(2)
        s.selectFrame(0); s.addFrame()                 // insert at 1
        #expect(s.referenceFrame == 3)
        s.moveFrame(from: 3, to: 0)
        #expect(s.referenceFrame == 0 && s.document().frames[0][0].name == "F2")
        s.reverseFrames()
        #expect(s.referenceFrame == 4)
        s.selectFrame(4); s.removeFrame()
        #expect(s.referenceFrame == nil)
        s.toggleReference(1); s.toggleReference(1)
        #expect(s.referenceFrame == nil)
    }
}
