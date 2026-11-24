import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ColorCycleTests {
    @Test func rotatesHue() {
        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        let g = ColorCycle.rotate(red, 1.0 / 3)
        #expect(abs(g.green - 1) < 0.001 && g.red < 0.001 && g.alpha == 0.5)
        let back = ColorCycle.rotate(red, 1)
        #expect(abs(back.red - 1) < 0.001 && back.green < 0.001)
        let grey = CodableColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
        #expect(ColorCycle.rotate(grey, 0.3) == grey)
    }

    @Test func cycleLoopsAndPulses() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100); s.newLayer()
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 9, y: 9, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 3)]
        #expect(s.colorCycle(count: 6) == 6)
        let c = s.document().frames.map { $0[1].strokes[0].color }
        #expect(c[0].red == 1 && c[2].green > 0.9 && c[4].blue > 0.9)
        s.undo(); s.selectFrame(0)
        #expect(s.colorCycle(count: 4, to: CodableColor(red: 0, green: 0, blue: 1, alpha: 1)) == 4)
        let p = s.document().frames.map { $0[1].strokes[0].color }
        #expect(p[0].red == 1 && abs(p[2].blue - 1) < 0.001)
    }
}
