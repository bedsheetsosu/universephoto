import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FootprintsTests {
    @Test func printsStayAndAlternate() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 300, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 10, y: 30, pressure: 1), InkPoint(x: 30, y: 70, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for k in 1..<12 { s.addFrame(); s.layers[1].transform.x = Double(k) * 20; s.changed() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.addFootprints(every: 2) == 6)                       // frames 1, 3, 5, 7, 9, 11
        let f = s.document().frames
        #expect(f[0][1].strokes.isEmpty && f[11][1].strokes.count == 6)
        let ys = f[11][1].strokes.map { ($0.points[0].y + $0.points[1].y) / 2 }
        #expect(ys[0] != ys[1] && abs(ys[0] - ys[2]) < 0.01)            // left, right, left
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
