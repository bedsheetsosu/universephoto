import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SkyArcTests {
    @Test func archFromLeftToRight() {
        let a = Studio.skyArc(0, width: 200, height: 100, rise: 0.4), m = Studio.skyArc(0.5, width: 200, height: 100, rise: 0.4), b = Studio.skyArc(1, width: 200, height: 100, rise: 0.4)
        #expect(a.dx == -100 && b.dx == 100 && m.dx == 0)
        #expect(abs(a.dy) < 1e-9 && abs(b.dy) < 1e-9 && abs(m.dy + 40) < 1e-9)
    }

    @Test func movesTheLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 150, pressure: 1), InkPoint(x: 110, y: 170, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 10)
        #expect(s.skyArcLayer() == 11)
        let f = s.document().frames
        #expect(f[0][1].transform.x == -100 && f[10][1].transform.x == 100)
        #expect(f[5][1].transform.y < -70)
    }
}
