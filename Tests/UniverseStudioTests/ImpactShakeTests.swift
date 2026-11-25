import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ImpactShakeTests {
    @Test func joltsEverythingAtTheLanding() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 90, pressure: 1), InkPoint(x: 110, y: 110, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<15 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        s.bounceLayer(height: 60, bounces: 2)
        let before = s.document().frames
        #expect(s.impactShake(strength: 8) == 1)
        let after = s.document().frames
        let moved = (0..<after.count).filter { after[$0][0].transform.x != before[$0][0].transform.x || after[$0][0].transform.y != before[$0][0].transform.y }
        #expect(moved.count >= 3 && moved.count <= 4)                // background moved too, a few frames
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[0].transform.x == 0 && $0[0].transform.y == 0 })
    }
}
