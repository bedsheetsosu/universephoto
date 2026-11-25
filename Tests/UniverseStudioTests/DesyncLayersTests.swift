import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct DesyncLayersTests {
    @Test func offsetsAreSpreadAndStable() {
        let o = Studio.desyncOffsets(count: 4, frameCount: 8)
        #expect(Set(o) == [0, 2, 4, 6])
        #expect(o == Studio.desyncOffsets(count: 4, frameCount: 8))
    }

    @Test func layersStopMovingInLockstep() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for (k, x) in [0.0, 10, 20, 30].enumerated() {
            if k > 0 { s.addFrame() }
            s.layers[0].transform.x = x; s.layers[1].transform.x = x; s.changed()
        }
        s.selectedIDs = Set(s.layers.map(\.id))
        #expect(s.desyncSelectedLayers() == 1)
        let f = s.document().frames
        #expect(f.map { $0[0].transform.x } != f.map { $0[1].transform.x })
        s.undo()
        #expect(s.document().frames.map { $0[0].transform.x } == s.document().frames.map { $0[1].transform.x })
    }
}
