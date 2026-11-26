import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ShakyTextTests {
    private func title() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        var t = InkStroke(points: [InkPoint(x: 40, y: 80, pressure: 1)], color: .black, width: 30)
        t.kind = "text"; t.text = "Brr"
        s.layers[1].strokes = [t]; s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 9)
        return s
    }

    @Test func eachLetterTremblesOnItsOwn() {
        let s = title()
        #expect(s.shakyLetters() == 3)
        let f = s.document().frames
        #expect(f.allSatisfy { $0[1].strokes.count == 3 })
        let dx = f.map { $0[1].strokes.map(\.points[0].x) }
        let base = Studio.letterStrokes(f[0][1].strokes[0]).count == 1
        #expect(base)
        // letters don't move in lockstep
        let d0 = zip(dx[1], dx[0]).map { $0 - $1 }
        #expect(Set(d0.map { ($0 * 100).rounded() }).count > 1)
        #expect(dx.joined().allSatisfy { abs($0) < 200 })
    }

    @Test func worksOnTextAlreadySplit() {
        let s = title()
        s.wavyText(hop: false)
        #expect(s.shakyLetters() == 3)
        #expect(s.undoStack.count >= 2)
    }

    @Test func ignoresLayersWithoutText() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 50, height: 50)
        s.addFrame()
        #expect(s.shakyLetters() == 0)
    }
}
