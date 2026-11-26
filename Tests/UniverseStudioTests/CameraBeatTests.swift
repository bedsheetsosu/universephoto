import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct CameraBeatTests {
    @Test func punchOnTheBeat() {
        #expect(Studio.beatZoom(0, amount: 0.05) == 0.05)
        #expect(Studio.beatZoom(0.5, amount: 0.05) < 0.01)
        #expect(Studio.beatZoom(1, amount: 0.05) == 0.05)
    }

    @Test func wholePictureZoomsIncludingSharedBackground() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 60, pressure: 1), InkPoint(x: 140, y: 160, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        #expect(s.cameraBeat(bpm: 120) == 24)
        let f = s.document().frames
        #expect(f[0].allSatisfy { $0.transform.scale > 1.04 })
        let mid = Int((s.fps / 4).rounded())
        #expect(f[mid][1].transform.scale < f[0][1].transform.scale)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.allSatisfy { $0.transform.scale == 1 } })
    }
}
