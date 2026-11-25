import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct LandingDustTests {
    @Test func findsTouchdowns() {
        #expect(Studio.landings([0, -40, -50, -40, 0, -30, -35, -30, 0, 0]) == [4, 8])   // landing, then the final touchdown
        #expect(Studio.landings([0, 10, 20, 30]).isEmpty)                    // just falling
        #expect(Studio.landings([0, 0, 0, 0]).isEmpty)
    }

    @Test func puffsAfterABounce() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 90, pressure: 1), InkPoint(x: 110, y: 110, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<15 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        s.bounceLayer(height: 60, bounces: 2)
        #expect(s.addLandingDust() == 1)                // the touchdown between the two hops
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 })
        #expect(f.filter { !$0[1].strokes.isEmpty }.count == 4)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
