import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct LettersDropInTests {
    @Test func bounceEasingLands() {
        #expect(Studio.bounceOut(0) == 0)
        #expect(abs(Studio.bounceOut(1) - 1) < 1e-9)
        #expect(Studio.bounceOut(0.36) > 0.95)          // first touchdown, then small rebounds
    }

    @Test func lettersComeInTurnAndAllLand() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        var t = InkStroke(points: [InkPoint(x: 40, y: 80, pressure: 1)], color: .black, width: 30)
        t.kind = "text"; t.text = "Hey"
        s.layers[1].strokes = [t]; s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        let rest = Studio.letterStrokes(t).map(\.points[0].y)
        #expect(s.lettersDropIn() == 3)
        let f = s.document().frames
        #expect(f[0][1].strokes.dropFirst().allSatisfy { $0.color.alpha == 0 })   // later letters not there yet
        #expect(f[0][1].strokes[0].points[0].y < 0)                                // first one starts above the picture
        #expect(f.last![1].strokes.map(\.points[0].y) == rest)                     // all landed
        #expect(f.last![1].strokes.allSatisfy { $0.color.alpha > 0 })
    }
}
