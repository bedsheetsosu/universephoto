import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct StrokeMorphTests {
    private func line(_ pts: [(Double, Double)], width: Double = 2) -> InkStroke {
        InkStroke(points: pts.map { InkPoint(x: $0.0, y: $0.1, pressure: 1) }, color: .black, width: width)
    }

    @Test func resampleIsEvenAlongTheLine() {
        let r = StrokeMorph.resample([InkPoint(x: 0, y: 0, pressure: 0), InkPoint(x: 10, y: 0, pressure: 1)], 3)
        #expect(r.map(\.x) == [0, 5, 10] && r[1].pressure == 0.5)
        let corner = StrokeMorph.resample([InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 10, y: 0, pressure: 1), InkPoint(x: 10, y: 10, pressure: 1)], 5)
        #expect(corner.map { [$0.x, $0.y] } == [[0, 0], [5, 0], [10, 0], [10, 5], [10, 10]])
    }

    @Test func morphsMatchingDrawingsOnly() {
        let a = [line([(0, 0), (10, 0)], width: 2)], b = [line([(0, 10), (5, 10), (10, 10)], width: 6)]
        let mid = StrokeMorph.strokes(a, b, 0.5)!
        #expect(mid[0].points.map(\.y) == [5, 5, 5] && mid[0].width == 4)
        #expect(StrokeMorph.strokes(a, b + b, 0.5) == nil, "different stroke count")
        var fill = a[0]; fill.kind = "fill"
        #expect(StrokeMorph.strokes([fill], [fill], 0.5) == nil)
    }

    @Test func tweenWithMorph() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 20, height: 20); s.newLayer()
        s.layers[1].strokes = [line([(0, 0), (10, 0)])]
        s.addFrame(); s.layers[1].strokes = [line([(0, 10), (10, 10)])]
        s.selectFrame(0)
        #expect(s.tweenToNext(from: 0, count: 1, eased: false, morph: true) == 1)
        #expect(s.document().frames[1][1].strokes[0].points.map(\.y) == [5, 5])
        s.undo()
        #expect(s.tweenToNext(from: 0, count: 1, eased: false, morph: false) == 1)
        #expect(s.document().frames[1][1].strokes[0].points.map(\.y) == [0, 0], "without morph the first drawing stays")
    }
}
