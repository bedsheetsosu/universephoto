import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct LineBoilTests {
    private func stroke() -> InkStroke {
        InkStroke(points: (0..<20).map { InkPoint(x: Double($0) * 5, y: 50, pressure: 1) }, color: .black, width: 2)
    }

    @Test func wobbleIsSmallSmoothAndRepeatable() {
        var r1 = LineBoil.RNG(state: 42), r2 = LineBoil.RNG(state: 42)
        let a = LineBoil.wobble(stroke(), amount: 2, rng: &r1), b = LineBoil.wobble(stroke(), amount: 2, rng: &r2)
        #expect(a.points == b.points)
        let d = zip(a.points, stroke().points).map { hypot($0.x - $1.x, $0.y - $1.y) }
        #expect(d.allSatisfy { $0 <= 2 * 2.0.squareRoot() + 1e-9 } && d.contains { $0 > 0.05 })
        let jumps = zip(a.points.dropFirst(), a.points).map { abs(($0.y - 50) - ($1.y - 50)) }
        #expect(jumps.allSatisfy { $0 < 2 }, "no zigzag between neighbours")
    }

    @Test func insertsCopiesOfTheActiveLayerOnly() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100); s.newLayer()
        s.layers[1].strokes = [stroke()]; s.layers[0].strokes = [stroke()]
        s.addFrame(); s.selectFrame(0); s.setHold(2, for: 0)
        #expect(s.lineBoil(after: 0, copies: 3) == 3)
        let d = s.document()
        #expect(d.frames.count == 5 && (1...3).allSatisfy { s.hold($0) == 2 })
        #expect(d.frames[1][1].strokes != d.frames[0][1].strokes && d.frames[1][1].strokes != d.frames[2][1].strokes)
        #expect(d.frames[1][0].strokes == d.frames[0][0].strokes, "other layers untouched")
        s.undo(); #expect(s.document().frames.count == 2)
    }
}
