import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct PinLayerStateTests {
    private func moving() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.layers[1].opacity = 1; s.changed()
        s.addFrame(); s.layers[1].transform.x = 30; s.layers[1].opacity = 0.5; s.changed()
        s.addFrame(); s.layers[1].transform.x = 60; s.changed()
        s.selectFrame(1)
        return s
    }

    @Test func everyFrameTakesTheCurrentState() {
        let s = moving()
        #expect(s.pinLayerStateToAllFrames() == 2)       // frames 0 and 2 differed
        let f = s.document().frames
        #expect(f.allSatisfy { $0[1].transform.x == 30 && $0[1].opacity == 0.5 })
    }

    @Test func oneUndoStep() {
        let s = moving()
        s.pinLayerStateToAllFrames()
        s.undo()
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 30, 60])
    }
}
