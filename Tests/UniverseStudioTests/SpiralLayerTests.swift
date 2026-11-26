import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SpiralLayerTests {
    @Test func landsOnItsPlace() {
        let first = Studio.spiralIn(0, of: 12, radius: 100, turns: 2)
        let last = Studio.spiralIn(11, of: 12, radius: 100, turns: 2)
        #expect(abs(first.dx - 100) < 1e-9 && abs(first.scale - 0.2) < 1e-9)
        #expect(last.dx == 0 && last.dy == 0 && last.scale == 1 && last.spin == 0)
        let mid = (1..<11).map { Studio.spiralIn($0, of: 12, radius: 100, turns: 2) }
        let dist = mid.map { hypot($0.dx, $0.dy) }
        #expect(zip(dist, dist.dropFirst()).allSatisfy { $1 <= $0 + 1e-9 })   // always closer
    }

    @Test func outIsTheReverse() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 90, pressure: 1), InkPoint(x: 110, y: 110, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<9 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.spiralLayer(radius: 60, turns: 1.5, out: true) > 0)
        let f = s.document().frames
        #expect(f[0][1].transform == LayerTransform())
        #expect(f[9][1].transform.scale < 0.5)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform == LayerTransform() })
    }
}
