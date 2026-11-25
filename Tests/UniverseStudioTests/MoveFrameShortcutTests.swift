import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct MoveFrameShortcutTests {
    @Test func currentFrameMovesAndStaysSelected() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 1, 2] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        s.selectFrame(1)
        s.moveFrame(from: s.frameIndex, to: s.frameIndex + 1)
        #expect(s.frameIndex == 2)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 2, 1])
        s.removeFrame()
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 2])
    }
}
