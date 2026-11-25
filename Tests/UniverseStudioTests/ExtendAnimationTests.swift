import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ExtendAnimationTests {
    @Test func appendsCopiesAndPicksThemAsPlayRange() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.layers[1].transform.x = 7; s.changed()
        #expect(s.extendAnimation(by: 3) == 3)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 7, 7, 7, 7])
        #expect(s.playRange == 1...4)
        s.undo()
        #expect(s.document().frames.count == 2)
    }
}
