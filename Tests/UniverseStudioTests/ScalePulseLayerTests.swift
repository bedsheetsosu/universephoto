import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ScalePulseLayerTests {
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 20, height: 20, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 5, y: 5, pressure: 1)], color: .black, width: 2)]
        s.layers[1].transform = LayerTransform(); s.changed()
        for _ in 1..<n { s.addFrame(); s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func factorIsOneAtEndsLargestInMiddle() {
        let n = 8, amount = 0.2
        let f = (0..<n).map { Studio.scalePulseFactor(frameIndexInRange: $0, count: n, amount: amount) }
        #expect(abs(f[0] - 1) < 1e-9)                          // no change at the ends
        #expect(abs(f[4] - (1 + amount)) < 1e-9)               // biggest at the middle
        #expect(f[2] == f[6])                                   // symmetric → loops cleanly
    }

    @Test func scalesTheLayerPerFrame() {
        let s = frames(8)
        #expect(s.scalePulseLayer(amount: 0.2) == 8)
        let sc = s.document().frames.map { $0[1].transform.scale }
        #expect(abs(sc[0] - 1) < 1e-9 && abs(sc[4] - 1.2) < 1e-9)
    }

    @Test func oneUndoStep() {
        let s = frames(6)
        s.scalePulseLayer(amount: 0.2)
        s.undo()
        #expect(s.document().frames.allSatisfy { abs($0[1].transform.scale - 1) < 1e-9 })
    }
}
