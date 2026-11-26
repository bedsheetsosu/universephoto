import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct CometTailTests {
    @Test func strongerNearTheHead() {
        let t = Studio.tailStrokes([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 0)], width: 10, colour: .black)
        #expect(t.count == 3)
        #expect(t[2].width > t[0].width && t[2].color.alpha > t[0].color.alpha)
        #expect(Studio.tailStrokes([CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)], width: 10, colour: .black).isEmpty)
    }

    @Test func followsTheWayItCame() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 300, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 10, y: 45, pressure: 1), InkPoint(x: 20, y: 55, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for k in 1..<10 { s.addFrame(); s.layers[1].transform.x = Double(k) * 20; s.changed() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.addCometTail(length: 4) == 9)                  // every frame but the first
        let f = s.document().frames
        #expect(f[0][1].strokes.isEmpty && f[6][1].strokes.count == 4)
        #expect(f[6][1].strokes.allSatisfy { $0.points.allSatisfy { $0.x <= 15 + 120 + 0.01 } })   // all behind the head
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
