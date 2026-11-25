import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RemoveDriftTests {
    @Test func walkStaysOnTheSpotButKeepsTheBob() {
        #expect(Studio.withoutDrift([0, 10, 20, 30]) == [0, 0, 0, 0])
        #expect(Studio.withoutDrift([0, 15, 20, 30]) == [0, 5, 0, 0])
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for (k, (x, y)) in [(0.0, 0.0), (10, -4), (20, 0), (30, -4)].enumerated() {
            if k > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.layers[1].transform.y = y; s.changed()
        }
        s.selectedLayer = 1
        s.removeDrift()
        let t = s.document().frames.map { $0[1].transform }
        #expect(t.allSatisfy { $0.x == 0 })
        #expect(t.map(\.y).contains { $0 != 0 })                       // the bob survives
        s.undo()
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 10, 20, 30])
    }
}
