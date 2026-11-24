import XCTest
@testable import UniverseStudio

final class TextLayoutTests: XCTestCase {
    private func text(_ t: String, align: TextAlign = .left, tracking: Double? = nil, spacing: Double? = nil) -> InkStroke {
        var s = InkStroke(points: [InkPoint(x: 100, y: 20, pressure: 1)], color: .black, width: 20)
        s.kind = "text"; s.text = t; s.textAlign = align == .left ? nil : align.rawValue; s.tracking = tracking; s.lineSpacing = spacing
        return s
    }
    private func width(_ r: (line: CTLine, x: Double, baseline: Double)) -> Double { CTLineGetTypographicBounds(r.line, nil, nil, nil) }

    func testLinesStackWithTheLineSpacing() {
        let rows = Renderer.textLines(text("One\nTwo\nThree", spacing: 1.5), at: CGPoint(x: 100, y: 20))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].baseline, 40, accuracy: 0.001, "First baseline one size below, as before")
        XCTAssertEqual(rows[1].baseline - rows[0].baseline, 30, accuracy: 0.001)
    }

    func testAlignmentAroundTheClick() {
        let p = CGPoint(x: 100, y: 20)
        let left = Renderer.textLines(text("Hello"), at: p)[0]
        let centre = Renderer.textLines(text("Hello", align: .center), at: p)[0]
        let right = Renderer.textLines(text("Hello", align: .right), at: p)[0]
        XCTAssertEqual(left.x, 100); XCTAssertEqual(centre.x + width(centre) / 2, 100, accuracy: 0.01); XCTAssertEqual(right.x + width(right), 100, accuracy: 0.01)
    }

    func testTrackingWidensTheLine() {
        let p = CGPoint(x: 0, y: 0)
        XCTAssertGreaterThan(width(Renderer.textLines(text("Spacing", tracking: 400), at: p)[0]), width(Renderer.textLines(text("Spacing"), at: p)[0]) + 20)
    }

    func testMultiLineTextRendersEveryLine() throws {
        var l = ArtLayer(name: "t"); l.strokes = [text("I\nI")]
        let img = try XCTUnwrap(Renderer.render(layers: [l], width: 200, height: 100))
        func inked(_ y0: Int, _ y1: Int) -> Bool { (y0..<y1).contains { y in (95..<115).contains { Renderer.sample(img, at: CGPoint(x: Double($0), y: Double(y))).alpha > 0.5 } } }
        XCTAssertTrue(inked(25, 40), "First line"); XCTAssertTrue(inked(49, 64), "Second line")
    }
}
