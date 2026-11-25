import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ArcLayerPathTests {
    @Test func straightMoveBulgesInTheMiddle() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 50, 100] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        s.selectedLayer = 1
        #expect(s.arcLayerPath(amount: 0.25) == 1)                  // only the middle moves
        let t = s.document().frames.map { $0[1].transform }
        #expect(t[0].y == 0 && t[2].y == 0)
        #expect(abs(t[1].y - 25) < 1e-9 || abs(t[1].y + 25) < 1e-9)
        s.undo()
        #expect(s.arcLayerPath(amount: 0.1) == 1)
        #expect(s.arcLayerPath(amount: 0) == 0)
    }

    @Test func needsTravel() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        #expect(s.arcLayerPath(amount: 0.25) == 0)
    }
}
