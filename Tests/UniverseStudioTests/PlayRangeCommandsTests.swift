import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct PlayRangeCommandsTests {
    @Test func spansTheSelectedFrames() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10)
        for _ in 0..<5 { s.addFrame() }
        s.selectFrame(1)
        s.clickFrame(4, command: false, shift: true)
        #expect(s.playRangeFromSelection())
        #expect(s.playRange == 1...4)
        s.selectedFrames = []
        #expect(!s.playRangeFromSelection())
    }
}
