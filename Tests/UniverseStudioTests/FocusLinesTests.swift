import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct FocusLinesTests {
    @Test func linesPointInAndLeaveAGap() {
        let c = CGPoint(x: 100, y: 100)
        let l = Studio.focusLines(count: 20, centre: c, gap: 40, reach: 200, width: 4, seed: 1)
        #expect(l.count == 20)
        for s in l {
            #expect(abs(hypot(s.points[0].x - c.x, s.points[0].y - c.y) - 200) < 1e-6)
            #expect(hypot(s.points[1].x - c.x, s.points[1].y - c.y) >= 40 - 1e-6)
            #expect(s.points[1].pressure < s.points[0].pressure)
        }
    }

    @Test func flickersEveryTwoFrames() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 90, pressure: 1), InkPoint(x: 110, y: 110, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 5)
        #expect(s.addFocusLines(count: 30) == 6)
        let f = s.document().frames
        #expect(f[0].last!.strokes.map(\.points) == f[1].last!.strokes.map(\.points))
        #expect(f[0].last!.strokes.map(\.points) != f[2].last!.strokes.map(\.points))
    }
}
