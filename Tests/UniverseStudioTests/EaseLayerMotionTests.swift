import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct EaseLayerMotionTests {
    @Test func evenGlideGetsSlowEnds() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 10, 20, 30, 40] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        s.selectedLayer = 1
        #expect(s.easeLayerMotion(.inOut) == 2)                        // ends and middle stay
        let xs = s.document().frames.map { $0[1].transform.x }
        #expect(xs[0] == 0 && xs[2] == 20 && xs[4] == 40)
        #expect(xs[1] < 10 && xs[3] > 30)
        s.undo()
        s.easeLayerMotion(.slowIn)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 2.5, 10, 22.5, 40])
    }
}
