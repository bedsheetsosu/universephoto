import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct FollowPathTests {
    @Test func sampleAlongAnLShape() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]
        let mid = FollowPath.sample(pts, at: 0.5)!, late = FollowPath.sample(pts, at: 0.75)!
        #expect(mid.0 == CGPoint(x: 10, y: 0) && late.0 == CGPoint(x: 10, y: 5) && late.1 == 90)
        let curve = CGMutablePath(); curve.move(to: .zero); curve.addCurve(to: CGPoint(x: 30, y: 0), control1: CGPoint(x: 10, y: 20), control2: CGPoint(x: 20, y: 20))
        let poly = FollowPath.polyline(curve)
        #expect(poly.count == 25 && poly.last == CGPoint(x: 30, y: 0) && poly.contains { $0.y > 10 })
    }

    @Test func layerTravelsTheRoute() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100); s.newLayer()
        var r = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 10, y: 10, pressure: 1)], color: .black, width: 1)
        r.kind = "rectangle"; r.filled = true
        s.layers[1].strokes = [r]
        #expect(s.followPath(count: 3, eased: false, orient: false) == 0, "no route yet")
        var p = PenPath(); p.nodes = [.init(anchor: CGPoint(x: 20, y: 50), out: nil), .init(anchor: CGPoint(x: 80, y: 50), out: nil)]
        s.penPath = p
        #expect(s.followPath(count: 3, eased: false, orient: true) == 3)
        let xs = s.document().frames.map { ($0[1].transform.x).rounded() }, ys = s.document().frames.map { ($0[1].transform.y).rounded() }
        #expect(xs == [15, 45, 75] && ys == [45, 45, 45])
        s.undo(); #expect(s.document().frames.count <= 1)
    }
}
