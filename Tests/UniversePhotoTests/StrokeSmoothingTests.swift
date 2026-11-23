import XCTest
@testable import UniversePhoto

final class StrokeSmoothingTests: XCTestCase {
    /// Eight samples on a circle of radius 40 (a fast mouse circle), closed.
    private var circle: [InkPoint] { (0...8).map { k in let a = Double(k) * .pi / 4; return InkPoint(x: 50 + 40 * cos(a), y: 50 + 40 * sin(a), pressure: 1) } }

    func testFastSamplesBecomeARoundCurve() throws {
        var s = InkStroke(points: circle, color: .black, width: 3)
        s.kind = nil
        var l = ArtLayer(name: "c"); l.strokes = [s]
        let img = try XCTUnwrap(Renderer.render(layers: [l], width: 100, height: 100))
        // Halfway between two samples the straight chord is 3 px inside the circle; the curve is on it.
        let a = Double.pi / 8, onArc = CGPoint(x: 50 + 40 * cos(a), y: 50 + 40 * sin(a))
        XCTAssertGreaterThan(Renderer.sample(img, at: onArc).alpha, 0.5)
    }

    func testSmoothingKeepsSamplesAndInterpolatesPressure() {
        let pts = [InkPoint(x: 0, y: 0, pressure: 0.2), InkPoint(x: 30, y: 0, pressure: 1), InkPoint(x: 60, y: 0, pressure: 0.2)]
        let out = Renderer.smoothed(pts, width: 10)
        XCTAssertGreaterThan(out.count, 10)
        for p in pts { XCTAssertTrue(out.contains(p), "Real samples stay") }
        XCTAssertTrue(out.allSatisfy { abs($0.y) < 0.001 }, "A straight line stays straight")
        XCTAssertTrue(out.allSatisfy { (0.2...1).contains($0.pressure) })
        XCTAssertEqual(Renderer.smoothed(Array(pts.prefix(2)), width: 10).count, 2, "Two points: nothing to curve")
    }

    func testCurveDoesNotOvershootSharpTurns() {
        let pts = [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 100, y: 0, pressure: 1), InkPoint(x: 100, y: 4, pressure: 1), InkPoint(x: 0, y: 4, pressure: 1)]
        let out = Renderer.smoothed(pts, width: 6)
        XCTAssertLessThan(out.map(\.x).max() ?? 0, 108, "Centripetal curve: no big loop past the turn")
    }
}
