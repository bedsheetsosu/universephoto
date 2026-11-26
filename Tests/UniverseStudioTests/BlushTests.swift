import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct BlushTests {
    @Test func fadesInThenGlows() {
        #expect(Studio.blushAlpha(0) == 0)
        #expect(Studio.blushAlpha(0.15) < Studio.blushAlpha(0.5))
        #expect((0...20).map { Studio.blushAlpha(0.3 + Double($0) * 0.035) }.allSatisfy { $0 > 0.65 })
    }

    @Test func twoCheeksOnANewLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 60, pressure: 1), InkPoint(x: 140, y: 160, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        #expect(s.addBlush() == 24)
        let f = s.document().frames
        #expect(f[0][2].strokes.isEmpty)
        #expect(f.last![2].strokes.filter { $0.kind == "ellipse" }.count == 2)
        #expect(f.last![2].strokes.count == 8)
    }
}
