import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct RollLayerTests {
    @Test func turnsMatchDistance() {
        #expect(abs(Studio.rollDegrees(distance: 2 * .pi * 10, radius: 10) - 360) < 1e-9)
        #expect(Studio.rollDegrees(distance: -5, radius: 10) < 0)
    }

    @Test func rollsAcrossWithoutSliding() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        var ball = InkStroke(points: [InkPoint(x: 20, y: 140, pressure: 1), InkPoint(x: 60, y: 180, pressure: 1)], color: .black, width: 1)
        ball.kind = "ellipse"; ball.filled = true
        s.layers[1].strokes = [ball]; s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 11)
        #expect(s.rollLayer(distance: 100) == 12)
        let last = s.document().frames.last![1].transform
        #expect(abs(last.rotation - Studio.rollDegrees(distance: 100, radius: 20)) < 1e-6)
        // the centre ends 100 to the right, at the same height
        let c0 = s.document().frames[0][1], c1 = s.document().frames.last![1]
        let b = s.contentBounds(c0)!
        let p0 = CGPoint(x: b.midX, y: b.midY).applying(s.matrix(c0.transform)), p1 = CGPoint(x: b.midX, y: b.midY).applying(s.matrix(c1.transform))
        #expect(abs(p1.x - p0.x - 100) < 1e-6 && abs(p1.y - p0.y) < 1e-6)
    }
}
