import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct StinkLinesTests {
    @Test func lineRisesAndThins() {
        let l = Studio.wavyLine(base: CGPoint(x: 50, y: 100), height: 60, amplitude: 5, phase: 0, colour: StinkStyle.stink.colour, width: 3)
        #expect(l.points.first!.y == 100 && abs(l.points.last!.y - 40) < 1e-9)
        #expect(l.points.last!.pressure < l.points.first!.pressure)
        let a = Studio.wavyLine(base: .zero, height: 60, amplitude: 5, phase: 0, colour: .black, width: 3).points
        let b = Studio.wavyLine(base: .zero, height: 60, amplitude: 5, phase: 1, colour: .black, width: 3).points
        #expect(zip(a, b).allSatisfy { abs($0.x - $1.x) < 1e-9 })                 // seamless loop
    }

    @Test func threeLinesAboveTheLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 120, pressure: 1), InkPoint(x: 140, y: 180, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 11)
        #expect(s.addStinkLines(.steam) == 12)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[2].strokes.count == 3 })
        #expect(f[0][2].strokes.allSatisfy { $0.points.allSatisfy { $0.y <= 117 } })
        #expect(f[0][2].name == L("Steam"))
    }
}
