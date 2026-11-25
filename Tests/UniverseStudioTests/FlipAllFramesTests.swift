import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FlipAllFramesTests {
    private func drawnFrames() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 40, background: .white)
        // Asymmetric mark on the left so a horizontal flip actually changes it.
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 4, y: 20, pressure: 1), InkPoint(x: 12, y: 20, pressure: 1)], color: .black, width: 4)]
        s.changed()
        s.addFrame(); s.changed()
        s.selectFrame(0)
        return s
    }

    @Test func everyFrameGetsTheLayerMirroredToPixels() {
        let s = drawnFrames()
        #expect(s.flipLayerAllFrames(horizontal: true) == 2)
        #expect(s.frames.count == 2)                          // no frames added
        let f = s.document().frames
        #expect(f.allSatisfy { $0[1].imageData != nil && $0[1].strokes.isEmpty })  // baked to pixels
    }

    @Test func oneUndoStep() {
        let s = drawnFrames()
        let before = s.document().frames.map { $0[1].strokes.count }
        s.flipLayerAllFrames(horizontal: true)
        s.undo()
        #expect(s.document().frames.map { $0[1].strokes.count } == before)
        #expect(s.document().frames.allSatisfy { $0[1].imageData == nil })
    }
}
