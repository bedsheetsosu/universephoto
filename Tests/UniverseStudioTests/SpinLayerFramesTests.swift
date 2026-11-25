import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SpinLayerFramesTests {
    @Test func turnsEvenlyAsALoop() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        #expect(s.spinLayerOverFrames(turns: 1) == 3)
        #expect(s.document().frames.map { $0[1].transform.rotation } == [0, 90, 180, 270])
        s.spinLayerOverFrames(turns: -1)
        #expect(s.document().frames.allSatisfy { $0[1].transform.rotation == 0 })
        s.undo(); s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.rotation == 0 })
    }
}
