import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct BoilAllFramesTests {
    private func drawnFrames() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 40, background: .white)
        let stroke = InkStroke(points: (0..<8).map { InkPoint(x: Double($0) * 4, y: 20, pressure: 1) }, color: .black, width: 3)
        s.layers[1].strokes = [stroke]; s.changed()
        s.addFrame(); s.changed()                            // frame 1 = copy, same stroke
        s.addFrame(); s.changed()                            // frame 2 = copy
        s.selectFrame(0)
        return s
    }

    @Test func everyFrameWobblesAndDiffers() {
        let s = drawnFrames()
        let before = s.document().frames.map { $0[1].strokes[0].points.map(\.y) }
        #expect(s.boilAllFrames(amount: 2) == 3)
        #expect(s.frames.count == 3)                          // no frames added
        let after = s.document().frames.map { $0[1].strokes[0].points.map(\.y) }
        #expect(zip(before, after).allSatisfy { $0 != $1 })   // each frame moved
        #expect(after[0] != after[1] && after[1] != after[2]) // and they differ from each other
    }

    @Test func deterministicSameResultTwice() {
        let a = drawnFrames(); a.boilAllFrames(amount: 2)
        let b = drawnFrames(); b.boilAllFrames(amount: 2)
        #expect(a.document().frames.map { $0[1].strokes[0].points.map(\.x) }
             == b.document().frames.map { $0[1].strokes[0].points.map(\.x) })
    }

    @Test func oneUndoStep() {
        let s = drawnFrames()
        let before = s.document().frames.map { $0[1].strokes[0].points.map(\.y) }
        s.boilAllFrames(amount: 2)
        s.undo()
        #expect(s.document().frames.map { $0[1].strokes[0].points.map(\.y) } == before)
    }
}
