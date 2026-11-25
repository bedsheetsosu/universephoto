import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct CopyMotionTests {
    @Test func followsRelativeToItsOwnStart() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)   // [background, sketch]
        s.layers[0].transform.x = 100; s.layers[1].transform.x = 0; s.changed()
        s.addFrame(); s.layers[1].transform.x = 30; s.layers[1].transform.scale = 2; s.changed()
        s.selectFrame(0)
        s.selectedLayer = 1
        s.selectedIDs = [s.layers[0].id, s.layers[1].id]
        #expect(s.copyMotionToSelected() == 1)                       // frame 0 already matches
        let f = s.document().frames
        #expect(f.map { $0[0].transform.x } == [100, 130])
        #expect(f[1][0].transform.scale == 2)
        s.undo()
        #expect(s.document().frames.map { $0[0].transform.x } == [100, 100])
    }
}
