import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ExpandHoldsTests {
    @Test func holdsBecomeFramesWithTheSameTiming() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 10, 20] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        s.setHold(3, for: 1)                          // frame 1 holds 3 ticks
        s.selectFrame(2)
        let length = s.animationDuration
        #expect(s.expandHolds() == 2)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 10, 10, 10, 20])
        #expect((0..<5).allSatisfy { s.hold($0) == 1 })
        #expect(abs(s.animationDuration - length) < 1e-9)
        #expect(s.frameIndex == 4)                    // still on the same drawing
        s.undo()
        #expect(s.document().frames.count == 3 && s.hold(1) == 3)
    }
}
