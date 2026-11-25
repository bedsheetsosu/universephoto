import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RemoveLayerAllFramesTests {
    /// Three frames, each with background (0) + a drawing layer (1, same id across frames).
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 2, y: 2, pressure: 1)], color: .black, width: 2)]; s.changed()
        for _ in 1..<n { s.addFrame(); s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func dropsTheLayerEverywhere() {
        let s = frames(3)
        let id = s.activeLayer!.id
        #expect(s.removeLayerFromAllFrames() == 3)
        #expect(s.document().frames.allSatisfy { f in !f.contains { $0.id == id } && f.count == 1 })
    }

    @Test func keepsTheLastLayerOfAFrame() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10)            // single layer, no background
        s.addFrame(); s.changed()
        #expect(s.removeLayerFromAllFrames() == 0)      // nothing removed, every frame has only one
        #expect(s.document().frames.allSatisfy { !$0.isEmpty })
    }

    @Test func oneUndoStep() {
        let s = frames(3)
        s.removeLayerFromAllFrames()
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
