import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct DeformLoopTests {
    let box = DeformLoop.Box(minX: 0, minY: 0, maxX: 100, maxY: 100)

    @Test func swayKeepsTheBottomAndJellyKeepsTheGround() {
        let bottom = DeformLoop.sway.move(30, 100, t: 0.25, box: box, strength: 1)
        #expect(bottom.0 == 30)
        let top = DeformLoop.sway.move(30, 0, t: 0.25, box: box, strength: 1)
        #expect(abs(top.0 - 42) < 1e-9)
        let ground = DeformLoop.jelly.move(80, 100, t: 0.25, box: box, strength: 1)
        #expect(ground.1 == 100 && ground.0 > 80)
        // Loops: t = 0 and t = 1 land in the same place.
        for d in DeformLoop.allCases {
            let a = d.move(37, 12, t: 0, box: box, strength: 1), b = d.move(37, 12, t: 1, box: box, strength: 1)
            #expect(abs(a.0 - b.0) < 1e-9 && abs(a.1 - b.1) < 1e-9)
        }
    }

    @Test func makesLoopFrames() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white); s.newLayer()
        s.layers[2].strokes = [InkStroke(points: [InkPoint(x: 10, y: 90, pressure: 1), InkPoint(x: 10, y: 10, pressure: 1)], color: .black, width: 3)]
        #expect(s.deformLoop(.sway, count: 8) == 8)
        let tops = s.document().frames.map { $0[2].strokes[0].points[1].x }
        #expect(tops[0] == 10 && tops[2] > 10 && tops[6] < 10)
        #expect(s.document().frames.allSatisfy { $0[2].strokes[0].points[0].x == 10 })
    }
}
