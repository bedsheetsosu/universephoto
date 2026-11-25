import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RepeatPlayRangeTests {
    @Test func copiesOnlyThePassageBehindItself() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 1, 2, 3] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        s.playRange = 1...2
        #expect(s.repeatPlayRange(times: 2) == 2)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 1, 2, 1, 2, 3])
        #expect(s.playRange == 1...4)
        s.undo()
        #expect(s.document().frames.count == 4)
    }

    @Test func needsAPlayRange() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10)
        s.addFrame()
        #expect(s.repeatPlayRange(times: 3) == 0)
    }
}
