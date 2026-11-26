import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SweatDropTests {
    @Test func swellsSlidesAndDrips() {
        let a = Studio.dropState(0.1), b = Studio.dropState(0.6), c = Studio.dropState(0.97)
        #expect(a.slide == 0 && a.size < b.size)
        #expect(b.slide > 0 && c.slide > b.slide)
        #expect(c.alpha < 0.3)
    }

    @Test func dropOnItsOwnLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 60, pressure: 1), InkPoint(x: 140, y: 140, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<15 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.addSweatDrop(drops: 2) == 2)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 })
        #expect(f.filter { !$0[2].strokes.isEmpty }.count > 10)
        let ys = f.compactMap { $0[2].strokes.dropFirst(2).first.map { ($0.points[0].y + $0.points[1].y) / 2 } }
        #expect(ys.max()! - ys.min()! > 30)                               // it really slides down
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
