import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct HitStopTests {
    @Test func holdsTheLandingFrame() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 90, pressure: 1), InkPoint(x: 110, y: 110, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<15 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        s.bounceLayer(height: 60, bounces: 2)
        let before = s.document().frames
        #expect(s.hitStop(extra: 3) == 1)
        let holds = (0..<s.frames.count).map { s.hold($0) }
        #expect(holds.filter { $0 == 4 }.count == 1 && holds.filter { $0 == 1 }.count == 15)
        #expect(s.document().frames == before)          // drawings untouched
        s.undo()
        #expect((0..<s.frames.count).allSatisfy { s.hold($0) == 1 })
    }

    @Test func nothingWithoutALanding() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 40, y: 40, pressure: 1)], color: .black, width: 6)]
        s.changed(); s.addFrame(); s.addFrame(); s.selectedLayer = 1
        #expect(s.hitStop(extra: 2) == 0)
        #expect(s.undoStack.isEmpty || s.undoStack.last?.label != "Hit stop")
    }
}
