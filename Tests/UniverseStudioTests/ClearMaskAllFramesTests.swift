import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ClearMaskAllFramesTests {
    @Test func dropsTheWipeEverywhere() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        s.wipeLayer(.topToBottom, reveal: true)
        #expect(s.clearMaskAllFrames() == 2)
        #expect(s.document().frames.allSatisfy { $0[1].mask == nil })
        s.undo()
        #expect(s.document().frames[0][1].mask != nil)
    }
}
