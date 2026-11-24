import CoreGraphics
import Testing
@testable import UniverseStudio

@MainActor
struct TextEditingTests {
    func studioWithText() -> (Studio, InkStroke) {
        let s = Studio()
        var t = InkStroke(points: [InkPoint(x: 100, y: 100, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 0.5), width: 40)
        t.kind = "text"; t.text = "Hallo"; t.fontName = "Helvetica-Bold"; t.textAlign = "center"
        s.add(t)
        return (s, t)
    }

    @Test func boundsCoverTheText() {
        let (_, t) = studioWithText()
        let b = Renderer.textBounds(t)
        #expect(b.width > 60 && b.height > 30)
        #expect(b.midX > 90 && b.midX < 110)   // centred on the click
        #expect(b.minY > 100 && b.minY < 120)  // starts about one cap height below
    }

    @Test func clickPicksTextAndChangesRewriteIt() throws {
        let (s, t) = studioWithText()
        let inside = CGPoint(x: Renderer.textBounds(t).midX, y: Renderer.textBounds(t).midY)
        #expect(s.beginTextEdit(at: inside))
        #expect(s.editingText == t.id && s.textContent == "Hallo" && s.textBold && s.brushSize == 40 && s.textAlign == .center)
        #expect(abs(s.brushOpacity - 0.5) < 0.001 && s.color.alpha == 1)
        s.textContent = "Tschüss"; s.brushSize = 60
        s.syncEditedText()
        let edited = try #require(s.activeLayer?.strokes.first { $0.id == t.id })
        #expect(edited.text == "Tschüss" && edited.width == 60 && abs(edited.color.alpha - 0.5) < 0.001)
        #expect(s.activeLayer?.strokes.filter { $0.kind == "text" }.count == 1)
        // Outside any text: nothing is picked.
        #expect(!s.beginTextEdit(at: CGPoint(x: 900, y: 700)) && s.editingText == nil)
    }
}
