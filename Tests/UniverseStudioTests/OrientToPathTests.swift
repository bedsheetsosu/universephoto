import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct OrientToPathTests {
    @Test func headingsFollowTheBend() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 10), CGPoint(x: 20, y: 20)]
        let h = Studio.headings(pts).map { $0! }
        #expect(h[0] == 0 && h[1] == 0)
        #expect(abs(h[4] - 90) < 1e-9)                 // heading down = clockwise 90° (y down)
        let still = Studio.headings([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0)])
        #expect(still.allSatisfy { $0 == nil })
    }

    @Test func neverJumpsAFullTurn() {
        // A circle run twice: headings keep growing instead of wrapping at ±180.
        let pts = (0..<40).map { k in CGPoint(x: cos(Double(k) * .pi / 10) * 50, y: sin(Double(k) * .pi / 10) * 50) }
        let h = Studio.headings(pts).map { $0! }
        #expect(zip(h, h.dropFirst()).allSatisfy { abs($1 - $0) < 90 })
        #expect(h.last! - h.first! > 540)
    }

    @Test func turnsTheLayerAlongADive() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 10, y: 50, pressure: 1), InkPoint(x: 30, y: 50, pressure: 1)], color: .black, width: 4)]
        s.changed()
        s.addFrame(); s.layers[1].transform.x = 40; s.changed()
        s.addFrame(); s.layers[1].transform.x = 80; s.changed()
        s.addFrame(); s.layers[1].transform.x = 80; s.layers[1].transform.y = 40; s.changed()
        s.addFrame(); s.layers[1].transform.x = 80; s.layers[1].transform.y = 80; s.changed()
        s.selectFrame(0); s.selectedLayer = 1
        let centres = s.document().frames.map { CGPoint(x: 20, y: 50).applying(s.matrix($0[1].transform)) }
        #expect(s.orientToPath() > 0)
        let f = s.document().frames
        #expect(f[0][1].transform.rotation == 0)
        #expect(abs(f[4][1].transform.rotation - 90) < 1e-6)
        for (k, fr) in f.enumerated() {                    // turned in place: the path is unchanged
            let c = CGPoint(x: 20, y: 50).applying(s.matrix(fr[1].transform))
            #expect(abs(c.x - centres[k].x) < 0.5 && abs(c.y - centres[k].y) < 0.5)
        }
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.rotation == 0 })
    }
}
