import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct ImpactZoomTests {
    @Test func punchesInAndEasesOut() {
        let z = (0..<6).map { Studio.impactZoom(age: $0, amount: 0.1) }
        #expect(z[0] == 0.1 && z[5] == 0)
        #expect(zip(z, z.dropFirst()).allSatisfy { $1 <= $0 })
    }

    @Test func zoomsTheWholePictureAtTheLanding() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 90, pressure: 1), InkPoint(x: 110, y: 110, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<15 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        s.bounceLayer(height: 60, bounces: 2)
        let before = s.document().frames
        #expect(s.impactZoom(amount: 0.08) == 1)
        let f = s.document().frames
        let zoomed = f.indices.filter { f[$0][0].transform.scale > 1 }
        #expect(!zoomed.isEmpty && zoomed.count <= 5)
        // A point of the ball keeps its place relative to the canvas middle, scaled by the zoom.
        let k = zoomed[0], z = f[k][0].transform.scale
        let p = CGPoint(x: 100, y: 100)
        let a = p.applying(s.matrix(before[k][1].transform)), b = p.applying(s.matrix(f[k][1].transform))
        #expect(abs((b.x - 100) - (a.x - 100) * z) < 0.01 && abs((b.y - 100) - (a.y - 100) * z) < 0.01)
        s.undo()
        #expect(s.document().frames == before)
    }
}
