import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct OrbitLayerTests {
    @Test func goesRoundAndStartsInPlace() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        #expect(s.orbitLayer(radius: 10) == 3)
        let t = s.document().frames.map { $0[1].transform }
        #expect(t[0].x == 0 && t[0].y == 0)
        #expect(abs(t[1].x - 10) < 1e-9 && abs(t[1].y + 10) < 1e-9)   // quarter turn
        #expect(abs(t[2].x) < 1e-9 && abs(t[2].y + 20) < 1e-9)        // top of the circle
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.y == 0 })
    }
}
