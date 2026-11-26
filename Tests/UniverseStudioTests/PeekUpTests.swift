import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct PeekUpTests {
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 60, pressure: 1), InkPoint(x: 110, y: 120, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<9 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        return s
    }

    @Test func risesFromItsBottomEdge() {
        let s = studio()
        #expect(s.riseUp() == 9)                                   // the last frame is fully up
        let f = s.document().frames
        #expect(f[0][1].transform.y > 50 && f[0][1].mask?.count == 1)
        #expect(f[9][1].transform == LayerTransform() && f[9][1].mask == nil)
        // The cut in layer space sits at the floor: bottom edge minus how far it was pushed down.
        let local = s.contentBounds(s.layers[1])!
        let cut = f[0][1].mask![0].points[0].y
        #expect(abs(cut - (local.maxY - f[0][1].transform.y)) < 0.01)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].mask == nil })
    }

    @Test func sinksBackDown() {
        let s = studio()
        #expect(s.riseUp(sink: true) == 9)
        let f = s.document().frames
        #expect(f[0][1].transform == LayerTransform() && f[9][1].transform.y > 50)
    }
}
