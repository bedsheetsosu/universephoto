import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct LettersPopInTests {
    @Test func backEasingOvershoots() {
        #expect(abs(Studio.backOut(0)) < 1e-9)
        #expect(abs(Studio.backOut(1) - 1) < 1e-9)
        #expect((0...20).map { Studio.backOut(Double($0) / 20) }.max()! > 1.05)
    }

    @Test func lettersGrowInTurnAndEndAtFullSize() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        var t = InkStroke(points: [InkPoint(x: 40, y: 80, pressure: 1)], color: .black, width: 30)
        t.kind = "text"; t.text = "Wow"
        s.layers[1].strokes = [t]; s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        let rest = Studio.letterStrokes(t)
        #expect(s.lettersPopIn() == 3)
        let f = s.document().frames
        #expect(f[0][1].strokes.dropFirst().allSatisfy { $0.color.alpha == 0 })
        #expect(f.contains { $0[1].strokes.contains { $0.width > 30 } })          // overshoot
        #expect(f.last![1].strokes.map(\.width) == rest.map(\.width))
        #expect(f.last![1].strokes.map(\.points[0]) == rest.map(\.points[0]))
    }
}
