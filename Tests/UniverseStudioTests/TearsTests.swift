import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct TearsTests {
    @Test func tearsFallAndFade() {
        #expect(Studio.tearState(0).down == 0)
        #expect(Studio.tearState(0.9).down > 0.8)
        #expect(Studio.tearState(0.99).alpha < 0.2)
    }

    @Test func twoEyesThreeDropsEach() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 60, pressure: 1), InkPoint(x: 140, y: 160, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        #expect(s.addTears() == 4)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && !$0[2].strokes.isEmpty })
        let xs = f[5][2].strokes.flatMap(\.points).map(\.x)
        #expect(xs.contains { $0 < 100 } && xs.contains { $0 > 100 })          // both sides
    }
}
