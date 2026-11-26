import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct StampLayerTests {
    @Test func comesDownBigAndFaint() {
        let a = Studio.stampLook(0, hit: 4), b = Studio.stampLook(3, hit: 4), c = Studio.stampLook(4, hit: 4)
        #expect(a.scale == 3 && a.alpha < 0.2)
        #expect(b.scale < a.scale && b.alpha > a.alpha)
        #expect(c.scale == 1 && c.alpha == 1)
    }

    @Test func hitsAndJolts() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 80, y: 90, pressure: 1), InkPoint(x: 120, y: 110, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<11 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.stampLayer(hitAfter: 4) == 4)
        let f = s.document().frames
        #expect(f[0][1].transform.scale == 3 && f[0][1].opacity < 0.2)
        #expect(f[4][0].transform.x != 0 || f[4][0].transform.y != 0)     // background jolts on the hit
        #expect(f[11][1].transform == LayerTransform() && f[11][1].opacity == 1)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform == LayerTransform() })
    }
}
