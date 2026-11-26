import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct EyeBlinkTests {
    @Test func blinksNowAndThenNotAtTheSeam() {
        let o = Studio.blinkOpenness(count: 72, gap: 24)
        #expect(o.first == 1 && o.last == 1)
        let shut = o.indices.filter { o[$0] == 0.1 }
        #expect(shut.count >= 2 && shut.count <= 4)
        #expect(zip(shut, shut.dropFirst()).allSatisfy { $1 - $0 >= 4 })
    }

    @Test func squashesFlatNotWider() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 40, y: 45, pressure: 1), InkPoint(x: 60, y: 55, pressure: 1)], color: .black, width: 4)]
        s.changed(); s.fps = 12
        for _ in 0..<35 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.eyeBlink(everySeconds: 1) >= 2)
        let t = s.document().frames.map { $0[1].transform }
        let shut = t.first { abs($0.scaleY - 0.1) < 1e-9 }
        #expect(shut != nil && abs(shut!.scaleX - 1) < 1e-9)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform == LayerTransform() })
    }
}
