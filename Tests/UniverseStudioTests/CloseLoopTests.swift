import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct CloseLoopTests {
    @Test func inBetweensLeadBackToTheFirstFrame() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].transform.x = 0
        s.addFrame()
        s.layers[1].transform.x = 40; s.changed()
        #expect(s.closeLoop(count: 3, eased: false) == 3)
        let xs = s.document().frames.map { $0[1].transform.x }
        #expect(xs.count == 5 && xs[2] == 30 && xs[3] == 20 && xs[4] == 10)
        #expect(s.hold(4) == 1)
        s.undo()
        #expect(s.document().frames.count == 2)
    }
}
