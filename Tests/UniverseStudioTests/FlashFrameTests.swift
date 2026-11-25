import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FlashFrameTests {
    private func twoFrames() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        s.addFrame(); s.layers[1].transform.x = 20; s.changed()
        s.selectFrame(0)
        return s
    }

    @Test func flashIsASolidFrameRightAfter() {
        let s = twoFrames()
        s.insertFlash(after: 0, color: .white)
        #expect(s.frames.count == 3)
        #expect(s.frameIndex == 1)                           // jumped onto the flash
        let flash = s.document().frames[1]
        #expect(flash.count == 1)
        let fill = flash[0].strokes.first
        #expect(fill?.kind == "fill" && fill?.color == .white)
        #expect(s.hold(1) == 1)
    }

    @Test func layersBuilderFillsWithTheColour() {
        let ls = Studio.flashFrameLayers(color: .black)
        #expect(ls.count == 1 && ls[0].strokes.count == 1)
        #expect(ls[0].strokes[0].kind == "fill" && ls[0].strokes[0].color == .black)
    }

    @Test func oneUndoStep() {
        let s = twoFrames()
        s.insertFlash(after: 0, color: .black)
        s.undo()
        #expect(s.frames.count == 2)
    }
}
