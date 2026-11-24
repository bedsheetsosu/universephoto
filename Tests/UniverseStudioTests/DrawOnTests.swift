import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct DrawOnTests {
    func line(_ x0: Double, _ x1: Double) -> InkStroke {
        InkStroke(points: [InkPoint(x: x0, y: 0, pressure: 1), InkPoint(x: x1, y: 0, pressure: 1)], color: .black, width: 4)
    }

    @Test func prefixCutsTheLine() {
        let p = DrawOn.prefix(line(0, 100).points, 25)
        #expect(p.count == 2 && abs(p[1].x - 25) < 0.001)
    }

    @Test func smoothGrowsAlongTotalLength() {
        let all = [line(0, 100), line(0, 100)]
        let half = DrawOn.strokes(all, step: 1, of: 2, byStroke: false)
        #expect(half.count == 1 && abs(half[0].points.last!.x - 100) < 0.001)
        let quarter = DrawOn.strokes(all, step: 1, of: 4, byStroke: false)
        #expect(quarter.count == 1 && abs(quarter[0].points.last!.x - 50) < 0.001)
        #expect(DrawOn.strokes(all, step: 4, of: 4, byStroke: false).count == 2)
    }

    @Test func drawOnMakesFramesAndKeepsText() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100); s.newLayer()
        var t = InkStroke(points: [InkPoint(x: 10, y: 10, pressure: 1)], color: .black, width: 20); t.kind = "text"; t.text = "Hi"
        s.layers[1].strokes = [line(0, 50), t, line(0, 80), line(0, 20)]
        #expect(s.drawOn(count: 0, byStroke: true, restTicks: 5) == 3)
        let f = s.document().frames.map { $0[1].strokes.count }
        #expect(f == [2, 3, 4] && s.hold(2) == 5)
        s.undo(); s.selectFrame(0)
        #expect(s.drawOn(count: 6, byStroke: false) == 6)
        #expect(s.document().frames.last?[1].strokes.count == 4)
    }
}
