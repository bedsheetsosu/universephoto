import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FrameTimingTests {
    private func studio(frames n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 20, height: 10)
        for _ in 1..<n { s.addFrame() }
        for i in 0..<n { s.selectFrame(i); s.layers[0].name = "F\(i)" }
        s.selectFrame(0)
        return s
    }
    private func names(_ s: Studio) -> [String] { s.document().frames.map { $0[0].name } }

    @Test func holdsExpandExportAndSurviveSaving() throws {
        let s = studio(frames: 3)
        s.setHold(3, for: 1)
        #expect(s.frameHolds == [1, 3, 1] && s.animationDuration == 5 / 12)
        let d = s.document()
        #expect(d.expandedFrames.map { $0[0].name } == ["F0", "F1", "F1", "F1", "F2"])
        let back = try JSONDecoder().decode(ArtDocument.self, from: JSONEncoder().encode(d))
        #expect(back.frameHolds == [1, 3, 1])
        s.setHold(1, for: 1)
        #expect(s.frameHolds.isEmpty, "all ones collapse")
        s.undo()
        #expect(s.hold(1) == 3)
    }

    @Test func holdsFollowInsertDeleteAndMove() {
        let s = studio(frames: 3)
        s.setHold(2, for: 2)
        s.selectFrame(0); s.addFrame()          // new frame at 1
        #expect(s.frameHolds == [1, 1, 1, 2])
        s.selectFrame(1); s.removeFrame()
        #expect(s.frameHolds == [1, 1, 2])
        s.selectFrame(0)
        s.moveFrame(from: 2, to: 0)
        #expect(names(s) == ["F2", "F0", "F1"] && s.frameHolds == [2, 1, 1])
        #expect(s.frameIndex == 1 && s.layers[0].name == "F0", "current frame follows its drawing")
        s.moveFrame(from: 1, to: 2)
        #expect(names(s) == ["F2", "F1", "F0"] && s.frameIndex == 2)
        s.undo()
        #expect(names(s) == ["F2", "F0", "F1"])
    }

    @Test func oldDocumentsWithoutHolds() {
        let d = ArtDocument(title: "x", width: 1, height: 1, layers: [], frames: [[], []])
        #expect(d.hold(0) == 1 && d.expandedFrames.count == 2)
    }
}
