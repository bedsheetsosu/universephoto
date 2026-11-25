import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct BounceLayerTests {
    @Test func hopsGetLowerAndLand() {
        #expect(Studio.bounceHeight(0, bounces: 2, decay: 0.5) == 0)
        #expect(Studio.bounceHeight(0.25, bounces: 2, decay: 0.5) == 1)     // top of the first hop
        #expect(Studio.bounceHeight(0.75, bounces: 2, decay: 0.5) == 0.5)   // second hop is half as high
        #expect(Studio.bounceHeight(1, bounces: 2, decay: 0.5) == 0)
    }

    @Test func liftsTheLayerAndUndoes() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for _ in 0..<4 { s.addFrame() }
        s.selectedLayer = 1
        #expect(s.bounceLayer(height: 100, bounces: 1) == 3)
        let ys = s.document().frames.map { $0[1].transform.y }
        #expect(ys == [0, -75, -100, -75, 0])
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.y == 0 })
    }
}
