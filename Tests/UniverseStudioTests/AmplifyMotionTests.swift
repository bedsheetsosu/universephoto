import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct AmplifyMotionTests {
    private func moving() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for (x, rot) in [(0.0, -10.0), (20, 0), (40, 10)] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.layers[1].transform.rotation = rot; s.changed()
        }
        return s
    }

    @Test func doublesAroundTheAverage() {
        let s = moving()
        #expect(s.amplifyMotion(factor: 2) == 2)              // the middle frame is the average
        let f = s.document().frames
        #expect(f.map { $0[1].transform.x } == [-20, 20, 60])
        #expect(f.map { $0[1].transform.rotation } == [-20, 0, 20])
    }

    @Test func halvingCalmsAndUndoRestores() {
        let s = moving()
        s.amplifyMotion(factor: 0.5)
        #expect(s.document().frames.map { $0[1].transform.x } == [10, 20, 30])
        s.undo()
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 20, 40])
    }
}
