import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct TypewriterTests {
    @Test func stepsByLetterAndWord() {
        #expect(Typewriter.steps("Hi you", byWord: false) == [1, 2, 3, 4, 5, 6])
        #expect(Typewriter.steps("Hello", byWord: false, perStep: 2) == [2, 4, 5])
        #expect(Typewriter.steps("Hi  you there", byWord: true) == [2, 7, 13])
    }

    @Test func textAppearsOverFrames() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100); s.newLayer()
        var t = InkStroke(points: [InkPoint(x: 10, y: 10, pressure: 1)], color: .black, width: 20); t.kind = "text"; t.text = "Hi yo"
        s.layers[1].strokes = [t]
        #expect(s.typewriter(byWord: true, restTicks: 6) == 2)
        let d = s.document()
        #expect(d.frames.map { $0[1].strokes.first?.text } == ["Hi", "Hi yo"] && s.hold(1) == 6)
        s.undo(); s.selectFrame(0)
        #expect(s.typewriter(byWord: false) == 5)
        #expect(s.document().frames[0][1].strokes[0].text == "H")
    }

    @Test func cursorWhileTypingOnly() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 50)
        var t = InkStroke(points: [InkPoint(x: 5, y: 5, pressure: 1)], color: .black, width: 12)
        t.kind = "text"; t.text = "Hi!"
        s.layers[0].strokes = [t]; s.changed(); s.selectedLayer = 0
        #expect(s.typewriter(byWord: false, cursor: true) == 3)
        let texts = s.document().frames.map { $0[0].strokes.first?.text ?? "" }
        #expect(texts == ["H|", "Hi|", "Hi!"])
    }
}
