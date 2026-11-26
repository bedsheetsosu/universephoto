import Testing
import Foundation
@testable import UniverseStudio

/// 0.246: camera effects move shared backgrounds too (as per-frame copies); locked layers stay.
@MainActor
struct CameraSharedTests {
    @Test func sharedBackgroundMovesWithTheCamera() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 50, y: 50, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<9 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 0
        s.toggleAllFrames()                                   // the background: same in all frames
        #expect(s.layers[0].allFrames == true)
        #expect(s.parallaxPan(distance: 80) > 0)
        let f = s.document().frames
        #expect(f[9][0].transform.x < -5 && f[9][0].allFrames == nil)
        s.undo()
        #expect(s.document().frames[9][0].allFrames == true)
    }
}
