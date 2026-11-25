import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct BreatheJellyTests {
    @Test func breatheLoopsAndJellySettles() {
        #expect(Studio.breatheStretch(0, of: 8, amount: 0.1) == 1)
        #expect(abs(Studio.breatheStretch(2, of: 8, amount: 0.1) - 1.1) < 1e-9)
        let j = (0..<12).map { Studio.jellyStretch($0, of: 12, amount: 0.3) }
        #expect(abs(j[1] - 1) > abs(j[10] - 1))          // dies down
    }

    @Test func multipliesOntoExistingStretchAndUndoes() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for _ in 0..<3 { s.addFrame() }
        s.selectedLayer = 1
        #expect(s.stretchEffect(jelly: false, amount: 0.1) == 2)   // frames 0 and 2 sit on the zero line
        #expect(abs((s.document().frames[1][1].transform.stretch ?? 1) - 1.1) < 1e-9)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.stretch == nil })
    }
}
