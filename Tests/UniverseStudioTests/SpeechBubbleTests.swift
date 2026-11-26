import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct SpeechBubbleTests {
    @Test func popsThenTypes() {
        let box = CGRect(x: 20, y: 20, width: 120, height: 50), tip = CGPoint(x: 30, y: 120)
        #expect(Studio.speechBubbleStrokes(t: 0, text: "Hi there", fontSize: 16, textWidth: 60, box: box, tip: tip).isEmpty)
        #expect(Studio.speechBubbleStrokes(t: 0.1, text: "Hi there", fontSize: 16, textWidth: 60, box: box, tip: tip).count == 4)
        let mid = Studio.speechBubbleStrokes(t: 0.3, text: "Hi there", fontSize: 16, textWidth: 60, box: box, tip: tip).last!
        let end = Studio.speechBubbleStrokes(t: 1, text: "Hi there", fontSize: 16, textWidth: 60, box: box, tip: tip).last!
        #expect(mid.kind == "text" && (mid.text ?? "").count < 8)
        #expect(end.text == "Hi there")
        #expect(mid.points[0] == end.points[0])                       // typing doesn't move the text
    }

    @Test func usesTheTextToolTextAndStaysInThePicture() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 120, y: 10, pressure: 1), InkPoint(x: 190, y: 60, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        #expect(s.speechBubbleText == L("Hello!"))
        s.textContent = "Wow!"
        s.extendAnimation(by: 23)
        #expect(s.addSpeechBubble() == 24)
        let f = s.document().frames
        #expect(f.last![2].strokes.last?.text == "Wow!")
        let pts = f.flatMap { $0[2].strokes.filter { $0.kind != "text" }.flatMap(\.points) }
        #expect(pts.allSatisfy { $0.x >= -5 && $0.x <= 205 && $0.y >= -5 && $0.y <= 205 })
    }
}
