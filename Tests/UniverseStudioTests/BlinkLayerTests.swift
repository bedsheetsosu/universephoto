import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct BlinkLayerTests {
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 2, y: 2, pressure: 1)], color: .black, width: 2)]; s.changed()
        for _ in 1..<n { s.addFrame(); s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func patternAlternates() {
        #expect((0..<6).map { Studio.blinkVisible(frameIndexInRange: $0, period: 1) } == [true, false, true, false, true, false])
        #expect((0..<6).map { Studio.blinkVisible(frameIndexInRange: $0, period: 2) } == [true, true, false, false, true, true])
    }

    @Test func blinkTogglesVisibilityPerFrame() {
        let s = frames(4)
        #expect(s.blinkLayer(period: 1) == 4)
        let vis = s.document().frames.map { $0[1].visible }
        #expect(vis == [true, false, true, false])
    }

    @Test func steadyRestoresAll() {
        let s = frames(4)
        s.blinkLayer(period: 1)
        #expect(s.steadyLayer() == 4)
        #expect(s.document().frames.allSatisfy { $0[1].visible })
    }

    @Test func oneUndoStep() {
        let s = frames(4)
        s.blinkLayer(period: 2)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].visible })
    }
}
