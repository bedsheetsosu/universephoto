import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RepeatLastEffectTests {
    @Test func runsTheSameEffectOnAnotherLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 50, y: 50, pressure: 1)], color: .black, width: 6)]
        s.newLayer(); s.layers[2].strokes = [InkStroke(points: [InkPoint(x: 20, y: 20, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<7 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.repeatLastEffect() == 0)                      // nothing yet
        s.onSelectedLayers { s.orbitLayer(radius: 20) }
        #expect(s.lastEffectLabel == "Orbit")
        s.selectedLayer = 2
        #expect(s.repeatLastEffect() > 0)
        let f = s.document().frames
        #expect(f[2][2].transform.x != 0 && f[2][1].transform.x != 0)
        s.undo()
        #expect(s.document().frames[2][2].transform == LayerTransform())   // its own undo step
    }
}
