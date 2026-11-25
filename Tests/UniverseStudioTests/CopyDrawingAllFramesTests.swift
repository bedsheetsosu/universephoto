import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct CopyDrawingAllFramesTests {
    private let dot = InkStroke(points: [InkPoint(x: 2, y: 2, pressure: 1)], color: .black, width: 2)

    @Test func drawingSpreadsButMotionStays() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.layers[1].transform.x = 30; s.changed()
        s.addFrame(); s.layers[1].transform.x = 60; s.changed()
        s.selectFrame(0); s.selectedLayer = 1
        s.layers[1].strokes = [dot]; s.changed()
        #expect(s.copyDrawingToAllFrames() == 2)
        let f = s.document().frames
        #expect(f.allSatisfy { $0[1].strokes == [self.dot] })
        #expect(f.map { $0[1].transform.x } == [0, 30, 60])
        s.undo()
        #expect(s.document().frames[2][1].strokes.isEmpty)
    }
}
