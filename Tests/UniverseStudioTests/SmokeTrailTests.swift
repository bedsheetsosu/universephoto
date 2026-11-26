import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct SmokeTrailTests {
    @Test func puffsGrowRiseAndFade() {
        let a = Studio.puffStroke(born: CGPoint(x: 50, y: 50), age: 0, size: 10, colour: .black)!
        let b = Studio.puffStroke(born: CGPoint(x: 50, y: 50), age: 4, size: 10, colour: .black)!
        #expect(b.points[1].x - b.points[0].x > a.points[1].x - a.points[0].x)
        #expect((b.points[0].y + b.points[1].y) < (a.points[0].y + a.points[1].y))   // higher up
        #expect(b.color.alpha < a.color.alpha)
    }

    @Test func trailBehindAMovingLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 300, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 10, y: 40, pressure: 1), InkPoint(x: 30, y: 60, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for k in 1..<10 { s.addFrame(); s.layers[1].transform.x = Double(k) * 25; s.changed() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.addSmokeTrail(every: 2) == 5)            // frames 1, 3, 5, 7, 9
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 })
        #expect(f[0][1].strokes.isEmpty && !f[5][1].strokes.isEmpty)
        // A puff stays where it was born, left of (behind) the layer.
        let puff = f[5][1].strokes[0], layerX = 20 + 5 * 25.0
        #expect((puff.points[0].x + puff.points[1].x) / 2 < layerX)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }

    @Test func noSmokeStandingStill() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 40, y: 40, pressure: 1)], color: .black, width: 6)]
        s.changed(); s.addFrame(); s.addFrame(); s.selectedLayer = 1
        #expect(s.addSmokeTrail() == 0)
    }
}
