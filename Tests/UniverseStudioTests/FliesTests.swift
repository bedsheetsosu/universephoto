import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FliesTests {
    @Test func fliesBuzzAndFlap() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 120, pressure: 1), InkPoint(x: 140, y: 180, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        #expect(s.addFlies(count: 3) == 3)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[2].strokes.count == 9 })
        #expect(f[0][2].strokes[0].points[0].y != f[1][2].strokes[0].points[0].y)   // moving / flapping
        let bodies = f.map { $0[2].strokes[2].points[0] }
        #expect(Set(bodies.map { "\($0.x.rounded())" }).count > 4)
    }
}
