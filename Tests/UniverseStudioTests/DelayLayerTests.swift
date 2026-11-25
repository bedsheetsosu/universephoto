import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct DelayLayerTests {
    private func moving() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 10, 20, 30] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        s.selectFrame(0)
        return s
    }

    @Test func loopsRoundWhenWrapping() {
        let s = moving()
        #expect(s.delayLayer(by: 1) == 4)
        #expect(s.document().frames.map { $0[1].transform.x } == [30, 0, 10, 20])
    }

    @Test func holdsTheFirstStateWithoutWrapping() {
        let s = moving()
        s.delayLayer(by: 2, wrap: false)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 0, 0, 10])
    }

    @Test func negativeRunsAheadAndUndoRestores() {
        let s = moving()
        s.delayLayer(by: -1)
        #expect(s.document().frames.map { $0[1].transform.x } == [10, 20, 30, 0])
        s.undo()
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 10, 20, 30])
    }
}
