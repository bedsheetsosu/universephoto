import XCTest
@testable import UniverseStudio

final class ShapeTests: XCTestCase {
    private func shape(_ kind: String, filled: Bool, parameter: Double? = nil, from p: CGPoint = CGPoint(x: 10, y: 10), to q: CGPoint = CGPoint(x: 70, y: 70)) throws -> CGImage {
        var l = ArtLayer(name: "s")
        var s = InkStroke(points: [InkPoint(x: p.x, y: p.y, pressure: 1), InkPoint(x: q.x, y: q.y, pressure: 1)], color: .black, width: 2)
        s.kind = kind; s.filled = filled ? true : nil; s.strength = parameter
        l.strokes = [s]
        return try XCTUnwrap(Renderer.render(layers: [l], width: 80, height: 80))
    }
    private func a(_ img: CGImage, _ x: Double, _ y: Double) -> Double { Renderer.sample(img, at: CGPoint(x: x, y: y)).alpha }

    func testFilledAndOutlinedRectangle() throws {
        XCTAssertGreaterThan(a(try shape("rectangle", filled: true), 40, 40), 0.9)
        let outline = try shape("rectangle", filled: false)
        XCTAssertEqual(a(outline, 40, 40), 0); XCTAssertGreaterThan(a(outline, 10, 40), 0.4)
    }

    func testRoundedCornersAreCut() throws {
        let img = try shape("roundedRect", filled: true, parameter: 20)
        XCTAssertEqual(a(img, 11, 11), 0, "Corner is round"); XCTAssertGreaterThan(a(img, 40, 11), 0.9)
    }

    func testPolygonAndStarPointUp() throws {
        let hex = try XCTUnwrap(ShapeGeometry.path(kind: "polygon", in: CGRect(x: 0, y: 0, width: 100, height: 100), parameter: 6))
        XCTAssertEqual(hex.boundingBox.minY, 0, accuracy: 0.001, "First corner at the top")
        let star = try shape("star", filled: true, parameter: 5)
        XCTAssertGreaterThan(a(star, 40, 40), 0.9, "Centre is filled")
        XCTAssertGreaterThan(a(star, 40, 12), 0.3, "Top point")
        XCTAssertEqual(a(star, 12, 40), 0, "Between the points stays empty")
        let tri = try XCTUnwrap(ShapeGeometry.path(kind: "polygon", in: CGRect(x: 0, y: 0, width: 10, height: 10), parameter: 1))
        XCTAssertFalse(tri.isEmpty, "Too few corners are clamped to a triangle")
    }

    func testArrowHasAHead() throws {
        let img = try shape("arrow", filled: false, from: CGPoint(x: 10, y: 40), to: CGPoint(x: 70, y: 40))
        XCTAssertGreaterThan(a(img, 30, 40), 0.9, "Shaft")
        XCTAssertGreaterThan(a(img, 62, 42.5), 0.5, "Head is wider than the shaft")
        XCTAssertEqual(a(img, 30, 43), 0)
    }

    func testOldDocumentsStayOutlines() throws {
        let json = #"{"id":"8C1C6A52-1B1A-4C9E-9E7A-2F0D7C5B1A11","points":[{"x":1,"y":1,"pressure":1},{"x":9,"y":9,"pressure":1}],"color":{"red":0,"green":0,"blue":0,"alpha":1},"width":1,"isEraser":false,"kind":"rectangle"}"#
        let s = try JSONDecoder().decode(InkStroke.self, from: Data(json.utf8))
        XCTAssertNil(s.filled)
    }
}
