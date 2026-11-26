import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct GroundShadowTests {
    @Test func shrinksAndFadesWithHeight() {
        let box = CGRect(x: 0, y: 0, width: 40, height: 40)
        let low = Studio.shadowStroke(box: box, groundY: 40, lift: 0)
        let high = Studio.shadowStroke(box: box, groundY: 40, lift: 1)
        func width(_ s: InkStroke) -> Double { abs(s.points[1].x - s.points[0].x) }
        #expect(width(low) == 40)
        #expect(width(high) < width(low))
        #expect(high.color.alpha < low.color.alpha)
        #expect(low.kind == "ellipse" && low.filled == true)
    }

    @Test func followsABounce() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 90, pressure: 1), InkPoint(x: 110, y: 110, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<11 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        s.bounceLayer(height: 60, bounces: 1)
        #expect(s.addGroundShadow() == 12)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[1].strokes.count == 1 })
        #expect(s.layers[s.selectedLayer].id == f[0][2].id)        // the drawing stays active
        let ys = f.map { $0[1].strokes[0].points[0].y + $0[1].strokes[0].points[1].y }
        #expect(Set(ys.map { ($0 * 100).rounded() }).count == 1)     // all on the same ground line
        let alphas = f.map { $0[1].strokes[0].color.alpha }
        #expect(alphas.min()! < alphas.max()!)                       // paler in the air
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
