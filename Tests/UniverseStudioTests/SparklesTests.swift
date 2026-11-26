import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SparklesTests {
    @Test func eachTwinklesOncePerLoop() {
        for c in 0..<5 {
            let sizes = (0..<20).map { Studio.sparkleSize(c, frame: $0, of: 20, total: 5) }
            #expect(sizes.contains { $0 > 0.5 })
            #expect(sizes.contains { $0 == 0 })
        }
        #expect(Studio.sparkleSize(0, frame: 0, of: 20, total: 5) == 0)   // starts invisible: seamless
    }

    @Test func newLayerAboveTheDrawing() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 80, y: 80, pressure: 1), InkPoint(x: 120, y: 120, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<11 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        let src = s.layers[1].id
        #expect(s.addSparkles(count: 5) == 5)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[1].id == src })
        #expect(f.contains { !$0[2].strokes.isEmpty })
        #expect(Set(f.map { $0[2].strokes.count }).count > 1)     // they come and go
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
