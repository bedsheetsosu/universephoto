import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct MirrorLayerMotionTests {
    @Test func pathFlipsAroundTheStart() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for (x, rot) in [(50.0, 0.0), (70, 10), (90, 20)] {
            if x > 50 { s.addFrame() }
            s.layers[1].transform.x = x; s.layers[1].transform.y = x; s.layers[1].transform.rotation = rot; s.changed()
        }
        s.selectedLayer = 1
        #expect(s.mirrorLayerMotion(horizontal: true) == 2)
        let t = s.document().frames.map { $0[1].transform }
        #expect(t.map(\.x) == [50, 30, 10])
        #expect(t.map(\.y) == [50, 70, 90])                            // vertical untouched
        #expect(t.map(\.rotation) == [0, -10, -20])
        s.undo()
        #expect(s.document().frames.map { $0[1].transform.x } == [50, 70, 90])
    }
}
