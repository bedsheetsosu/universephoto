import XCTest
@testable import UniverseStudio

final class BrushTipTests: XCTestCase {
    private func stroke(_ tip: BrushTip, id: UUID = UUID()) -> InkStroke {
        var s = InkStroke(points: (0...12).map { InkPoint(x: 10 + Double($0) * 6, y: 40, pressure: 1) }, color: .black, width: 16)
        s.id = id; s.brushTip = tip == .round ? nil : tip.rawValue
        return s
    }
    private func render(_ s: InkStroke) throws -> CGImage {
        var l = ArtLayer(name: "b"); l.strokes = [s]
        return try XCTUnwrap(Renderer.render(layers: [l], width: 100, height: 80))
    }
    private func a(_ img: CGImage, _ x: Double, _ y: Double) -> Double { Renderer.sample(img, at: CGPoint(x: x, y: y)).alpha }

    func testDabsAreEvenlySpaced() {
        let d = Renderer.dabs(stroke(.airbrush), spacing: { _ in 5 })
        XCTAssertEqual(d.count, 15, "72 px at 5 px plus the start")
        for (x, y) in zip(d, d.dropFirst()) { XCTAssertEqual(hypot(y.0.x - x.0.x, y.0.y - x.0.y), 5, accuracy: 0.001) }
    }

    func testEveryTipPaintsAlongTheStroke() throws {
        for tip in BrushTip.allCases {
            let img = try render(stroke(tip))
            // Spray and chalk are dots: look for ink near the line, not at one exact pixel.
            let ink = (36...44).flatMap { y in (40...50).map { a(img, Double($0), Double(y)) } }.max() ?? 0
            XCTAssertGreaterThan(ink, 0.05, tip.rawValue)
            XCTAssertEqual(a(img, 45, 5), 0, tip.rawValue)
        }
    }

    func testMarkerIsTranslucentAndEven() throws {
        let img = try render(stroke(.marker))
        XCTAssertEqual(a(img, 30, 40), 0.55, accuracy: 0.03)
        XCTAssertEqual(a(img, 33, 40), a(img, 30, 40), accuracy: 0.02, "No darker overlaps")
    }

    func testAirbrushIsSoftAtTheEdge() throws {
        let img = try render(stroke(.airbrush))
        XCTAssertGreaterThan(a(img, 45, 40), a(img, 45, 50))
        XCTAssertGreaterThan(a(img, 45, 50), 0)
    }

    func testSprayIsTheSameEveryTime() throws {
        let id = UUID()
        let one = try render(stroke(.spray, id: id)), two = try render(stroke(.spray, id: id))
        XCTAssertEqual(PixelOps.bitmap(one)?.bytes, PixelOps.bitmap(two)?.bytes)
    }
}
