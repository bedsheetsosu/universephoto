import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct WeatherMoreTests {
    @Test(arguments: [Weather.confetti, .bubbles, .fireflies])
    func loopsWithoutASeam(_ w: Weather) {
        let ps = Weather.particles(w, width: 400, height: 300)
        let a = Weather.strokes(w, ps, t: 0, width: 400, height: 300)
        let b = Weather.strokes(w, ps, t: 1, width: 400, height: 300)
        #expect(!a.isEmpty && a.count == b.count)
        for (s0, s1) in zip(a, b) {
            #expect(zip(s0.points, s1.points).allSatisfy { abs($0.x - $1.x) < 1e-6 && abs($0.y - $1.y) < 1e-6 })
        }
    }

    @Test func confettiMakesAColourfulLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        #expect(s.addWeather(.confetti, count: 12) == 12)
        let colours = Set(s.document().frames[3].last!.strokes.map { "\($0.color.red)-\($0.color.blue)" })
        #expect(colours.count >= 3)
    }
}
