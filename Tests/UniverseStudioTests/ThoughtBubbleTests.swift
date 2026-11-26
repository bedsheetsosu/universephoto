import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct ThoughtBubbleTests {
    @Test func buildsUpOverTime() {
        let c = CGPoint(x: 100, y: 50), from = CGPoint(x: 60, y: 120)
        #expect(Studio.thoughtBubbleStrokes(t: 0, from: from, cloud: c, radius: 30).isEmpty)
        #expect(Studio.thoughtBubbleStrokes(t: 0.1, from: from, cloud: c, radius: 30).count == 2)    // one small bubble
        #expect(Studio.thoughtBubbleStrokes(t: 0.25, from: from, cloud: c, radius: 30).count == 4 + 12)
        let dots = (0..<12).map { Studio.thoughtBubbleStrokes(t: 0.32 + Double($0) * 0.04, from: from, cloud: c, radius: 30).count - 16 }
        #expect(Set(dots) == [1, 2, 3])
    }

    @Test func addsALayerAboveThatStaysInThePicture() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 150, y: 20, pressure: 1), InkPoint(x: 190, y: 60, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        let steps = s.undoStack.count
        #expect(s.addThoughtBubble() == 24)
        #expect(s.undoStack.count == steps + 1)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[2].name == L("Thought bubble") })
        let pts = f.flatMap { $0[2].strokes.flatMap(\.points) }
        #expect(!pts.isEmpty)
        #expect(pts.allSatisfy { $0.x >= -5 && $0.x <= 205 && $0.y >= -5 && $0.y <= 205 })
    }
}
