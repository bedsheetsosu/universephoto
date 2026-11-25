import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RainbowFramesTests {
    private func redFrames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 2, y: 2, pressure: 1)], color: red, width: 2)]; s.changed()
        for _ in 1..<n { s.addFrame(); s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func hueTurnsProgressivelyFirstFrameUntouched() {
        let s = redFrames(4)
        #expect(s.rainbowAllFrames() == 4)
        let cols = s.document().frames.map { $0[1].strokes[0].color }
        #expect(cols[0].red == 1 && cols[0].green == 0 && cols[0].blue == 0)   // frame 0 unchanged (0 turns)
        #expect(cols[1] != cols[0] && cols[2] != cols[1])                       // each frame a different hue
    }

    @Test func rotateIsAFullCircleAtOne() {
        let red = CodableColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        let back = ColorCycle.rotate(red, 1)
        #expect(abs(back.red - red.red) < 1e-9 && abs(back.green - red.green) < 1e-9 && abs(back.blue - red.blue) < 1e-9)
    }

    @Test func oneUndoStep() {
        let s = redFrames(4)
        s.rainbowAllFrames()
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].strokes[0].color.green == 0 && $0[1].strokes[0].color.blue == 0 })
    }
}
