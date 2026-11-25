import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct CropToRangeTests {
    private func frames(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        for k in 1..<n { s.addFrame(); s.layers[1].transform.x = Double(k); s.changed() }
        s.selectFrame(0)
        return s
    }

    @Test func keepsOnlyTheRange() {
        let s = frames(6)
        s.playRange = 2...4
        s.selectFrame(3)
        #expect(s.cropToPlayRange() == 3)
        #expect(s.document().frames.map { $0[1].transform.x } == [2, 3, 4])
        #expect(s.playRange == nil)
        #expect(s.layers[1].transform.x == 3)          // still on the same drawing
    }

    @Test func withoutARangeNothingHappens() {
        let s = frames(4)
        #expect(s.cropToPlayRange() == 0)
        #expect(s.frames.count == 4)
    }

    @Test func oneUndoStep() {
        let s = frames(5)
        s.playRange = 1...2
        s.cropToPlayRange()
        s.undo()
        #expect(s.frames.count == 5)
    }
}
