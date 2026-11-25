import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct GrowLayerFramesTests {
    @Test func growsFromAlmostNothingAndUndoes() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        #expect(s.growLayerOverFrames(grow: true) == 2)
        #expect(s.document().frames.map { $0[1].transform.scale } == [0.01, 0.5, 1])
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.scale == 1 })
        s.growLayerOverFrames(grow: false)
        #expect(s.document().frames.map { $0[1].transform.scale } == [1, 0.5, 0.01])
    }
}
