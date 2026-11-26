import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct DizzyStarsTests {
    @Test func ringIsTiltedWithDepth() {
        let c = CGPoint(x: 100, y: 50)
        let front = Studio.dizzyStar(0, of: 4, t: 0.125, centre: c, radius: 40)   // angle π/2 → front
        let back = Studio.dizzyStar(0, of: 4, t: 0.375, centre: c, radius: 40)    // angle 3π/2 → back
        #expect(front.1 > back.1 && front.2 > back.2)
        #expect(abs(front.0.y - c.y) < 40 * 0.3)
        // seamless loop: t = 1 matches t = 0
        let a = Studio.dizzyStar(1, of: 3, t: 0, centre: c, radius: 40).0, b = Studio.dizzyStar(1, of: 3, t: 1, centre: c, radius: 40).0
        #expect(abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6)
    }

    @Test func addsStarsAboveTheLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 70, y: 100, pressure: 1), InkPoint(x: 130, y: 180, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        #expect(s.addDizzyStars(count: 3) == 24)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[2].strokes.count == 6 })
        #expect(f.allSatisfy { $0[2].strokes.allSatisfy { $0.points[1].y < 110 } })
    }
}
