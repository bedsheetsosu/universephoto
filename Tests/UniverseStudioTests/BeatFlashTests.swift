import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct BeatFlashTests {
    @Test func flashesOnTheBeatOnly() {
        #expect(Studio.beatFlash(0, strength: 0.5) == 0.5)
        #expect(Studio.beatFlash(0.5, strength: 0.5) == 0)
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 50, height: 50, background: .white)
        s.extendAnimation(by: 23)
        #expect(s.addBeatFlash(bpm: 120) == 24)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.last!.blend == .screen })
        #expect(f[0].last!.opacity == 0.5)
        #expect(f.contains { $0.last!.opacity == 0 })
    }
}
