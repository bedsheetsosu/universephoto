import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct CountdownTests {
    @Test func popsThenFades() {
        let a = Studio.countdownLook(frame: 0, of: 12), mid = Studio.countdownLook(frame: 6, of: 12), end = Studio.countdownLook(frame: 11, of: 12)
        #expect(a.size == 1.5 && a.alpha == 1)
        #expect(mid.size == 1 && mid.alpha == 1)
        #expect(end.alpha < 0.5)
    }

    @Test func oneSecondPerNumber() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 100, background: .white)
        s.fps = 12
        #expect(s.countdown(from: 3) == 36)
        let f = s.document().frames
        #expect(f.count == 36)
        #expect(f[0].last!.strokes.first?.text == "3" && f[12].last!.strokes.first?.text == "2" && f[30].last!.strokes.first?.text == "1")
        #expect(Set(f.map { $0.last!.id }).count == 1)        // one layer throughout
        s.undo()
        #expect(s.document().frames.count <= 1)
    }
}
