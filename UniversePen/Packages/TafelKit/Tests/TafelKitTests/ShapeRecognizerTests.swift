import XCTest
import CoreGraphics
@testable import TafelKit

final class ShapeRecognizerTests: XCTestCase {
    /// Deterministic hand wobble.
    private func wobble(_ p: [CGPoint], amount: Double = 2) -> [CGPoint] {
        p.enumerated().map { i, q in CGPoint(x: q.x + sin(Double(i) * 1.7) * amount, y: q.y + cos(Double(i) * 2.3) * amount) }
    }

    private func path(_ corners: [CGPoint], closed: Bool, step: Double = 4) -> [CGPoint] {
        RecognizedShape.polygon(corners, closed: closed).sampled(spacing: step)
    }

    func testLine() {
        let s = ShapeRecognizer.recognize(wobble(path([CGPoint(x: 10, y: 10), CGPoint(x: 300, y: 120)], closed: false)))
        XCTAssertEqual(s?.name, "line")
    }

    func testCircle() {
        let c = RecognizedShape.ellipse(center: CGPoint(x: 200, y: 200), rx: 100, ry: 100, angle: 0).sampled(spacing: 4)
        XCTAssertEqual(ShapeRecognizer.recognize(wobble(c, amount: 3))?.name, "circle")
    }

    func testEllipse() {
        let e = RecognizedShape.ellipse(center: CGPoint(x: 200, y: 200), rx: 160, ry: 70, angle: 0.4).sampled(spacing: 4)
        guard case .ellipse(_, let rx, let ry, let angle)? = ShapeRecognizer.recognize(wobble(e)) else { return XCTFail() }
        XCTAssertEqual(rx, 160, accuracy: 8); XCTAssertEqual(ry, 70, accuracy: 8); XCTAssertEqual(angle, 0.4, accuracy: 0.08)
    }

    func testSquareIsNotACircle() {
        let sq = path([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 3), CGPoint(x: 198, y: 205), CGPoint(x: -2, y: 200)], closed: true)
        guard case .polygon(let c, true)? = ShapeRecognizer.recognize(wobble(sq)) else { return XCTFail() }
        XCTAssertEqual(c.count, 4)
        // Snapped to an exact, axis-aligned rectangle.
        XCTAssertEqual(c[0].y, c[1].y, accuracy: 0.001)
        XCTAssertEqual(c[1].x, c[2].x, accuracy: 0.001)
    }

    func testTriangle() {
        let t = path([CGPoint(x: 0, y: 200), CGPoint(x: 120, y: 0), CGPoint(x: 240, y: 200)], closed: true)
        XCTAssertEqual(ShapeRecognizer.recognize(wobble(t))?.name, "triangle")
    }

    func testScribbleIsNothing() {
        let scribble = (0..<200).map { i in CGPoint(x: Double(i) * 2, y: sin(Double(i) / 3) * 60) }
        XCTAssertNil(ShapeRecognizer.recognize(scribble))
    }

    func testTinyStrokeIsNothing() {
        XCTAssertNil(ShapeRecognizer.recognize([CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 2), CGPoint(x: 5, y: 1), CGPoint(x: 6, y: 4)]))
    }

    func testArrowWithOneBarb() {
        let p = path([CGPoint(x: 0, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 250, y: 70)], closed: false)
        XCTAssertEqual(ShapeRecognizer.recognize(wobble(p, amount: 1.5))?.name, "arrow")
    }

    func testArrowWithTwoBarbs() {
        let p = path([CGPoint(x: 0, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 250, y: 70),
                      CGPoint(x: 300, y: 100), CGPoint(x: 250, y: 130)], closed: false)
        XCTAssertEqual(ShapeRecognizer.recognize(wobble(p, amount: 1.5))?.name, "arrow")
    }

    func testChevronIsNotAnArrow() {
        // Two equally long legs: a polyline, not an arrow.
        let p = path([CGPoint(x: 0, y: 200), CGPoint(x: 150, y: 0), CGPoint(x: 300, y: 200)], closed: false)
        XCTAssertNotEqual(ShapeRecognizer.recognize(wobble(p))?.name, "arrow")
    }
}
