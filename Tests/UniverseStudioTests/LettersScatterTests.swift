import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct LettersScatterTests {
    @Test func holdsThenFliesOffAndFades() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        var t = InkStroke(points: [InkPoint(x: 40, y: 80, pressure: 1)], color: .black, width: 30)
        t.kind = "text"; t.text = "Bye"
        s.layers[1].strokes = [t]; s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        let rest = Studio.letterStrokes(t).map(\.points[0])
        #expect(s.lettersScatter() == 3)
        let f = s.document().frames
        #expect(f[0][1].strokes.map(\.points[0]) == rest)                  // still at the start
        let last = f.last![1].strokes
        #expect(last.allSatisfy { $0.color.alpha == 0 })                    // gone at the end
        #expect(zip(last, rest).allSatisfy { $0.points[0].y < $1.y })        // all went up
        #expect(Studio.scatterProgress(frame: 0, frames: 24) == 0)
        #expect(Studio.scatterProgress(frame: 23, frames: 24) == 1)
    }
}
