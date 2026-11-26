import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct WanderLayerTests {
    @Test func startsHereLoopsAndStaysNearby() {
        let p = (0...48).map { Studio.wanderOffset($0, of: 48, radius: 30, seed: 7) }
        #expect(abs(p[0].0) < 1e-9 && abs(p[0].1) < 1e-9)
        #expect(abs(p[48].0) < 1e-9 && abs(p[48].1) < 1e-9)
        #expect(p.allSatisfy { hypot($0.0, $0.1) < 30 * 4 })
        #expect(p.contains { hypot($0.0, $0.1) > 10 })
        let other = Studio.wanderOffset(12, of: 48, radius: 30, seed: 8)
        #expect(other.0 != p[12].0)                            // another seed, another path
    }

    @Test func movesTheLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 50, y: 50, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<23 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.wanderLayer(radius: 20) > 0)
        #expect(Set(s.document().frames.map { $0[1].transform.x }).count > 10)
    }
}
