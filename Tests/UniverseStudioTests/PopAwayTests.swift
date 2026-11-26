import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct PopAwayTests {
    @Test func swellsThenBursts() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 90, pressure: 1), InkPoint(x: 110, y: 110, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<15 { s.addFrame() }
        s.selectFrame(8); s.selectedLayer = 1
        #expect(s.popAway() == 8)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 })
        #expect(f[7][1].transform.scale > 1.2 && f[4][1].transform.scale == 1)
        #expect(f[8][1].opacity == 0 && f[15][1].opacity == 0 && f[7][1].opacity == 1)
        #expect(f[7][2].strokes.isEmpty && !f[8][2].strokes.isEmpty)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 && $0[1].opacity == 1 })
    }
}
