import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct WavyTextTests {
    private func text(_ t: String, align: String? = nil) -> InkStroke {
        var s = InkStroke(points: [InkPoint(x: 100, y: 20, pressure: 1)], color: .black, width: 30)
        s.kind = "text"; s.text = t; s.fontName = "Helvetica-Bold"; s.textAlign = align
        return s
    }

    @Test func splitsIntoLettersInPlace() {
        let parts = Studio.letterStrokes(text("Hi yo", align: "center"))
        #expect(parts.map { $0.text } == ["H", "i", "y", "o"])            // the space is skipped
        let xs = parts.map { $0.points[0].x }
        #expect(xs == xs.sorted() && xs[0] < 100 && xs[3] > 100)          // centred around x = 100
        #expect(parts.allSatisfy { $0.points[0].y == 20 && $0.textAlign == nil })
    }

    @Test func lettersRenderLikeTheWholeText() {
        let whole = text("Wave", align: "center")
        var a = ArtLayer(name: "a"); a.strokes = [whole]
        var b = ArtLayer(name: "b"); b.strokes = Studio.letterStrokes(whole)
        let ia = Renderer.render(layers: [a], width: 200, height: 80)!, ib = Renderer.render(layers: [b], width: 200, height: 80)!
        #expect(Renderer.alphaBounds(ia).map { Int($0.minX) } == Renderer.alphaBounds(ib).map { Int($0.minX) })
    }

    @Test func lettersMoveInTurn() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 80, background: .white)
        s.layers[1].strokes = [text("Wave")]; s.changed()
        for _ in 0..<11 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.wavyText(hop: false) == 4)
        let f = s.document().frames
        #expect(f.allSatisfy { $0[1].strokes.count == 4 })
        let ys = f[3][1].strokes.map { $0.points[0].y }
        #expect(Set(ys).count > 1)                                          // different heights at once
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].strokes.count == 1 })
    }
}
