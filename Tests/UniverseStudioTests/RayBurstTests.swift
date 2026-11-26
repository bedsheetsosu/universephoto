import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct RayBurstTests {
    @Test func wedgesTurnOneStepPerLoop() {
        let c = CGPoint(x: 50, y: 50)
        let a = Studio.rayWedges(count: 8, t: 0, centre: c, reach: 100)
        let b = Studio.rayWedges(count: 8, t: 1, centre: c, reach: 100)
        #expect(a.count == 8 && a.allSatisfy { $0.count == 3 })
        // after one loop each ray sits where the next one started
        #expect(abs(b[0][1].x - a[1][1].x) < 1e-6 && abs(b[0][1].y - a[1][1].y) < 1e-6)
    }

    @Test func goesBelowTheLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 60, pressure: 1), InkPoint(x: 140, y: 160, pressure: 1)], color: .black, width: 8)]
        let id = s.layers[1].id
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        #expect(s.addRayBurst(rays: 12) == 24)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[1].strokes.count == 12 && $0[2].id == id })
        #expect(f[0][1].strokes[0].color.alpha < 0.5)
        #expect(s.layers[s.selectedLayer].id == id)
    }
}
