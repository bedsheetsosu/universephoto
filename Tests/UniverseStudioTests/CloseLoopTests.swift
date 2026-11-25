import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct CloseLoopTests {
    @Test func inBetweensLeadBackToTheFirstFrame() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].transform.x = 0
        s.addFrame()
        s.layers[1].transform.x = 40; s.changed()
        #expect(s.closeLoop(count: 3, curve: .linear) == 3)
        let xs = s.document().frames.map { $0[1].transform.x }
        #expect(xs.count == 5 && xs[2] == 30 && xs[3] == 20 && xs[4] == 10)
        #expect(s.hold(4) == 1)
        s.undo()
        #expect(s.document().frames.count == 2)
    }
}

@MainActor
struct CrossfadeTests {
    @Test func mixIsLinearAndOpaque() throws {
        let size = (width: 4, height: 4)
        func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
            let c = Renderer.context(width: 4, height: 4)!
            c.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            return c.makeImage()!
        }
        let m = try #require(Tween.mix(solid(1, 0, 0), solid(0, 0, 1), 0.5, size))
        let px = Renderer.sample(m, at: CGPoint(x: 2, y: 2))
        #expect(abs(px.red - 0.5) < 0.03 && abs(px.blue - 0.5) < 0.03 && px.alpha > 0.98)
    }

    @Test func crossfadedInBetweensBecomePixels() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 40, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 5, y: 5, pressure: 1), InkPoint(x: 30, y: 30, pressure: 1)], color: .black, width: 4)]
        s.changed(); s.addFrame()
        // Two strokes against one: can't morph, so the drawings fade.
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 5, y: 30, pressure: 1), InkPoint(x: 20, y: 5, pressure: 1)], color: .black, width: 4),
                               InkStroke(points: [InkPoint(x: 20, y: 5, pressure: 1), InkPoint(x: 35, y: 30, pressure: 1)], color: .black, width: 4)]
        s.changed()
        #expect(s.tweenToNext(from: 0, count: 2, curve: .linear, morph: true, crossfade: true) == 2)
        let f = s.document().frames
        #expect(f[1][1].strokes.isEmpty && f[1][1].imageData != nil && f[0][1].strokes.count == 1)
        #expect(f[1][0].imageData == f[0][0].imageData)   // unchanged background left alone
    }
}
