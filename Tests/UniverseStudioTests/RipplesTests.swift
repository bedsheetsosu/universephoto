import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RipplesTests {
    @Test func ringsAreStaggeredAndLoop() {
        #expect(Studio.rippleAge(0, rings: 3, frame: 0, of: 12) == 0)
        #expect(abs(Studio.rippleAge(1, rings: 3, frame: 0, of: 12) - 1.0 / 3) < 1e-9)
        #expect(abs(Studio.rippleAge(0, rings: 3, frame: 6, of: 12) - 0.5) < 1e-9)
        #expect(Studio.rippleAge(2, rings: 3, frame: 4, of: 12) == 0)           // wrapped round
        let young = Studio.rippleStroke(centre: .zero, age: 0.3, reach: 100, flat: false, colour: .black)!
        let old = Studio.rippleStroke(centre: .zero, age: 0.8, reach: 100, flat: false, colour: .black)!
        #expect(old.points[1].x > young.points[1].x && old.color.alpha < young.color.alpha)
        let flat = Studio.rippleStroke(centre: .zero, age: 0.5, reach: 100, flat: true, colour: .black)!
        #expect(flat.points[1].y < flat.points[1].x)
    }

    @Test func layerBelowTheDrawing() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 95, y: 95, pressure: 1), InkPoint(x: 105, y: 105, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<11 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        let src = s.layers[1].id
        #expect(s.addRipples(rings: 3) == 3)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[2].id == src && !$0[1].strokes.isEmpty })
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
