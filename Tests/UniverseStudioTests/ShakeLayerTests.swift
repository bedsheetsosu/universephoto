import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ShakeLayerTests {
    @Test func offsetsAreDeterministicAndBounded() {
        let a = Studio.shakeOffsets(count: 50), b = Studio.shakeOffsets(count: 50)
        #expect(a.map(\.0) == b.map(\.0))
        #expect(a.allSatisfy { abs($0.0) <= 1 && abs($0.1) <= 1 && abs($0.2) <= 1 })
        #expect(Set(a.map(\.0)).count > 40)                      // really varies
    }

    @Test func shakesWithinTheAmountAndUndoes() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        #expect(s.shakeLayer(amount: 5) == 3)
        let xs = s.document().frames.map { $0[1].transform.x }
        #expect(xs.allSatisfy { abs($0) <= 5 } && Set(xs).count == 3)
        #expect(s.document().frames.allSatisfy { $0[0].transform.x == 0 })
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.x == 0 })
    }
}
