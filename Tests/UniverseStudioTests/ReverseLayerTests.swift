import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ReverseLayerTests {
    @Test func onlyTheActiveLayerRunsBackwards() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 10, 20] {
            if x > 0 { s.addFrame() }
            s.layers[0].transform.x = x; s.layers[1].transform.x = x; s.changed()
        }
        s.selectedLayer = 1
        #expect(s.reverseLayerOnly() == 2)
        let f = s.document().frames
        #expect(f.map { $0[1].transform.x } == [20, 10, 0])
        #expect(f.map { $0[0].transform.x } == [0, 10, 20])
        s.undo()
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 10, 20])
    }
}
