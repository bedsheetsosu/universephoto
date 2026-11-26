import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ParallaxPanTests {
    @Test func nearLayersMoveMore() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 100, background: .white)
        s.newLayer(); s.newLayer()
        for _ in 0..<9 { s.addFrame() }
        s.selectFrame(0)
        #expect(s.parallaxPan(distance: 100) > 0)
        let last = s.document().frames[9]
        let xs = last.map(\.transform.x)
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $0 > $1 })                  // each layer up moves further
        #expect(abs(xs.last! + 100) < 1e-9 && abs(xs[0] + 15) < 1e-9)
        #expect(s.document().frames[0].allSatisfy { $0.transform.x == 0 })
    }
}
