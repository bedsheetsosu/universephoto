import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct SpeedLinesTests {
    private let dot = InkStroke(points: [InkPoint(x: 40, y: 40, pressure: 1), InkPoint(x: 60, y: 60, pressure: 1)], color: .black, width: 4)

    @Test func linesTrailBehindTheMove() {
        let box = CGRect(x: 100, y: 100, width: 20, height: 20)
        let ls = Studio.speedLineStrokes(box: box, velocity: CGVector(dx: 30, dy: 0), color: .black)
        #expect(ls.count == 5)
        #expect(ls.allSatisfy { $0.points[1].x < $0.points[0].x && $0.points[0].x < box.minX })   // to the left
        #expect(Studio.speedLineStrokes(box: box, velocity: CGVector(dx: 1, dy: 0), color: .black).isEmpty)
    }

    @Test func newLayerBelowOnlyWhereItMoves() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [dot]; s.changed()
        for x in [0.0, 0, 40, 80] {
            s.addFrame(); s.layers[1].transform.x = x; s.changed()
        }
        s.selectFrame(0); s.selectedLayer = 1
        let id = s.layers[1].id
        #expect(s.addSpeedLines() == 2)                     // frames 3 and 4 move, 1 and 2 stand still
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[2].id == id })   // lines sit below the layer
        #expect(f[4][1].strokes.count == 5 && f[2][1].strokes.isEmpty)
        #expect(s.activeLayer?.id == id)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
