import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct StepLayerMotionTests {
    @Test func holdsEverySecondFrame() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 10, 20, 30, 40] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        s.selectedLayer = 1
        #expect(s.stepLayerMotion(every: 2) == 2)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 0, 20, 20, 40])
        s.undo()
        s.stepLayerMotion(every: 3)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 0, 0, 30, 30])
    }
}
