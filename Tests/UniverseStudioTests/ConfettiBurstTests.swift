import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct ConfettiBurstTests {
    @Test func startsEmptySpreadsAndFades() {
        let c = CGPoint(x: 100, y: 100)
        #expect(Studio.burstStrokes(.confetti, t: 0, centre: c, size: 200).isEmpty)
        let mid = Studio.burstStrokes(.confetti, t: 0.4, centre: c, size: 200)
        #expect(mid.count == 70 && mid.contains { abs($0.points[0].x - 100) > 30 })
        #expect(Studio.burstStrokes(.sparks, t: 1, centre: c, size: 200).isEmpty)
    }

    @Test func makesFramesFromOneAndIsOneUndoStep() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        #expect(s.addBurst(.sparks, count: 10) == 10)
        #expect(s.document().frames.allSatisfy { $0.count == 3 })
        s.undo()
        #expect(s.document().frames.count <= 1 && s.layers.count == 2)
    }
}
