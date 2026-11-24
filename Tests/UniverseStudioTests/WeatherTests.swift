import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct WeatherTests {
    @Test func loopsWithoutASeam() {
        let ps = Weather.particles(.snow, width: 300, height: 200)
        let a = Weather.strokes(.snow, ps, t: 0, width: 300, height: 200), b = Weather.strokes(.snow, ps, t: 1, width: 300, height: 200)
        #expect(a.count == b.count && zip(a, b).allSatisfy { abs($0.points[0].y - $1.points[0].y) < 0.001 || abs(abs($0.points[0].y - $1.points[0].y) - 200) < 0.001 })
        #expect(Weather.particles(.rain, width: 300, height: 200).count == Weather.particles(.rain, width: 300, height: 200).count)
    }

    @Test func weatherLayerOverFrames() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 100, background: .white)
        #expect(s.addWeather(.rain, count: 6) == 6)
        let f = s.document().frames
        #expect(f.count == 6 && f.allSatisfy { $0.count == 3 } && Set(f.map { $0[2].id }).count == 1)
        #expect(f[0][2].strokes != f[1][2].strokes)
        #expect(s.addWeather(.sparkle, count: 0) == 6 && s.document().frames[3].count == 4)
    }
}
