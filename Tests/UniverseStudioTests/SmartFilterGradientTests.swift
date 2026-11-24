import XCTest
@testable import UniverseStudio

final class SmartFilterGradientTests: XCTestCase {
    private func filled(_ c: CodableColor) -> ArtLayer {
        var l = ArtLayer(name: "f")
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: c, width: 1)
        f.kind = "fill"; l.strokes = [f]
        return l
    }
    private func render(_ l: ArtLayer, _ w: Int = 40, _ h: Int = 40) throws -> CGImage { try XCTUnwrap(Renderer.render(layers: [l], width: w, height: h)) }

    func testFilterStackSurvivesSavingAndOldDocumentsHaveNone() throws {
        var l = filled(.white)
        var off = SmartFilter(kind: .twirl); off.enabled = false; off.amount = -4
        l.filters = [SmartFilter(kind: .sepia), off]
        let back = try JSONDecoder().decode(ArtLayer.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.filters, l.filters)
        let old = try JSONDecoder().decode(ArtLayer.self, from: Data(#"{"name":"old"}"#.utf8))
        XCTAssertNil(old.filters)
    }

    func testSepiaTintsAndADisabledFilterDoesNothing() throws {
        var l = filled(CodableColor(red: 0.2, green: 0.4, blue: 1, alpha: 1))
        let plain = Renderer.sample(try render(l), at: CGPoint(x: 20, y: 20))
        var sepia = SmartFilter(kind: .sepia); sepia.amount = 1
        l.filters = [sepia]
        let toned = Renderer.sample(try render(l), at: CGPoint(x: 20, y: 20))
        XCTAssertGreaterThan(toned.red, toned.blue, "Sepia is warm")
        l.filters![0].enabled = false
        let off = Renderer.sample(try render(l), at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(off.blue, plain.blue, accuracy: 0.01)
        XCTAssertEqual(off.red, plain.red, accuracy: 0.01)
    }

    func testEveryFilterKeepsTheDocumentSize() throws {
        let base = try render(filled(CodableColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1)), 32, 24)
        for kind in SmartFilter.Kind.allCases {
            let out = try XCTUnwrap(Renderer.filtered(base, [SmartFilter(kind: kind)]), kind.rawValue)
            XCTAssertEqual(out.width, 32, kind.rawValue); XCTAssertEqual(out.height, 24, kind.rawValue)
            if let r = kind.range { XCTAssertTrue(r.contains(kind.defaultAmount), kind.rawValue) }
        }
    }

    private func gradient(_ style: GradientStyle, from p: CGPoint, to q: CGPoint) throws -> CGImage {
        var l = ArtLayer(name: "g")
        var g = InkStroke(points: [InkPoint(x: p.x, y: p.y, pressure: 1), InkPoint(x: q.x, y: q.y, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1)
        g.kind = style.kind; g.secondaryColor = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        l.strokes = [g]
        return try render(l, 60, 60)
    }

    func testRadialGradientRunsFromTheCentreOutwards() throws {
        let img = try gradient(.radial, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 50, y: 30))
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 30, y: 30)).red, 0.9)
        for corner in [CGPoint(x: 2, y: 2), CGPoint(x: 57, y: 57), CGPoint(x: 30, y: 55)] {
            XCTAssertGreaterThan(Renderer.sample(img, at: corner).blue, 0.9, "\(corner)")
        }
    }

    func testReflectedGradientMirrorsAroundTheStart() throws {
        let img = try gradient(.reflected, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 50, y: 30))
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 30, y: 30)).red, 0.9)
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 55, y: 30)).blue, 0.9)
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 5, y: 30)).blue, 0.9, "Mirrored side")
        let lin = try gradient(.linear, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 50, y: 30))
        XCTAssertGreaterThan(Renderer.sample(lin, at: CGPoint(x: 5, y: 30)).red, 0.9, "Linear keeps the start colour before the start")
    }

    func testThresholdMakesBlackAndWhite() throws {
        var l = filled(CodableColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1))
        var t = SmartFilter(kind: .threshold); t.amount = 0.5
        l.filters = [t]
        XCTAssertGreaterThan(Renderer.sample(try render(l), at: CGPoint(x: 20, y: 20)).red, 0.95)
        l.filters![0].amount = 0.8
        XCTAssertLessThan(Renderer.sample(try render(l), at: CGPoint(x: 20, y: 20)).red, 0.05)
    }

    func testNoiseVariesPixelsButKeepsTransparencyAndDustRemovesSpecks() throws {
        // Half the layer filled grey: noise changes neighbouring pixels differently, the empty half stays empty.
        var l = ArtLayer(name: "n")
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1), width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 20, y: 40, pressure: 1)]
        l.strokes = [f]; l.filters = [SmartFilter(kind: .addNoise)]
        let img = try render(l)
        let values = (0..<10).map { Renderer.sample(img, at: CGPoint(x: Double($0) + 0.5, y: 10.5)).red }
        XCTAssertGreaterThan(values.max()! - values.min()!, 0.03)
        XCTAssertEqual(Renderer.sample(img, at: CGPoint(x: 30, y: 10)).alpha, 0)
        // A single white speck on black disappears under dust & scratches.
        var d = filled(.black)
        var speck = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1)
        speck.kind = "fill"; speck.selectionPoints = [InkPoint(x: 20, y: 20, pressure: 1), InkPoint(x: 21, y: 21, pressure: 1)]
        d.strokes.append(speck)
        XCTAssertGreaterThan(Renderer.sample(try render(d), at: CGPoint(x: 20.5, y: 20.5)).red, 0.9)
        d.filters = [SmartFilter(kind: .dustAndScratches)]
        XCTAssertLessThan(Renderer.sample(try render(d), at: CGPoint(x: 20.5, y: 20.5)).red, 0.1)
    }
}
