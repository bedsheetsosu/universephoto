import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct PauseAtEndTests {
    @Test func lastFrameHoldsLongerAndUndoes() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10)
        s.addFrame(); s.addFrame()
        s.fps = 12
        #expect(s.addPauseAtEnd(seconds: 1) == 13)
        #expect(s.hold(0) == 1 && s.hold(2) == 13)
        #expect(s.addPauseAtEnd(seconds: 10) == 99)                   // capped
        s.undo(); s.undo()
        #expect(s.hold(2) == 1)
    }
}
