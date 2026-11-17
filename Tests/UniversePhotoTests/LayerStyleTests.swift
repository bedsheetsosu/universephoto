import XCTest
@testable import UniversePhoto

final class LayerStyleTests: XCTestCase {
    /// An opaque white 10×10 square in the middle of a 40×40 document.
    private func square() -> ArtLayer {
        var l = ArtLayer(name: "sq")
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 15, y: 15, pressure: 1), InkPoint(x: 25, y: 25, pressure: 1)]
        l.strokes = [f]
        return l
    }
    private func render(_ l: ArtLayer) throws -> CGImage { try XCTUnwrap(Renderer.render(layers: [l], width: 40, height: 40)) }

    func testDropShadowFallsAwayFromTheLight() throws {
        var l = square()
        l.style = LayerStyle(); l.style!.shadow.on = true; l.style!.shadow.angle = 90; l.style!.shadow.distance = 8; l.style!.shadow.blur = 0; l.style!.shadow.opacity = 1
        let img = try render(l)
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 20, y: 30)).alpha, 0.9, "Light from the top: shadow below")
        XCTAssertEqual(Renderer.sample(img, at: CGPoint(x: 20, y: 10)).alpha, 0, "Nothing above")
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 20, y: 20)).red, 0.9, "The square stays on top")
    }

    func testGlowAndOutlineSurroundTheShape() throws {
        var l = square()
        l.style = LayerStyle(); l.style!.outline.on = true; l.style!.outline.width = 3; l.style!.outline.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let outlined = try render(l)
        let ring = Renderer.sample(outlined, at: CGPoint(x: 13, y: 20))
        XCTAssertGreaterThan(ring.red, 0.9); XCTAssertLessThan(ring.green, 0.1)
        XCTAssertEqual(Renderer.sample(outlined, at: CGPoint(x: 8, y: 20)).alpha, 0)
        l.style!.outline.on = false; l.style!.glow.on = true; l.style!.glow.size = 6
        let glowing = try render(l)
        XCTAssertGreaterThan(Renderer.sample(glowing, at: CGPoint(x: 13, y: 20)).alpha, 0.05, "Glow outside the edge")
    }

    func testColorOverlayKeepsTheShape() throws {
        var l = square()
        l.style = LayerStyle(); l.style!.overlay.on = true; l.style!.overlay.color = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        let img = try render(l)
        let inside = Renderer.sample(img, at: CGPoint(x: 20, y: 20))
        XCTAssertGreaterThan(inside.blue, 0.9); XCTAssertLessThan(inside.red, 0.1)
        XCTAssertEqual(Renderer.sample(img, at: CGPoint(x: 5, y: 5)).alpha, 0)
    }

    func testStylesFollowAMovedLayerAndOldLayersHaveNone() throws {
        var l = square(); l.transform.x = 10
        l.style = LayerStyle(); l.style!.overlay.on = true; l.style!.overlay.color = CodableColor(red: 0, green: 1, blue: 0, alpha: 1)
        let img = try render(l)
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 30, y: 20)).green, 0.9)
        XCTAssertEqual(Renderer.sample(img, at: CGPoint(x: 17, y: 20)).alpha, 0)
        let json = #"{"name":"old","visible":true,"strokes":[],"opacity":1,"blend":"normal","locked":false}"#
        XCTAssertNil(try JSONDecoder().decode(ArtLayer.self, from: Data(json.utf8)).style)
    }
}

final class InnerStyleTests: XCTestCase {
    /// White 20×20 square at (10, 10) in a 40×40 document.
    private func square() -> ArtLayer {
        var l = ArtLayer(name: "sq")
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 10, y: 10, pressure: 1), InkPoint(x: 30, y: 30, pressure: 1)]
        l.strokes = [f]
        return l
    }
    private func render(_ l: ArtLayer) throws -> CGImage { try XCTUnwrap(Renderer.render(layers: [l], width: 40, height: 40)) }

    func testInnerShadowDarkensTheLitEdgeOnly() throws {
        var l = square(); l.style = LayerStyle()
        l.style!.innerShadow.on = true; l.style!.innerShadow.angle = 90; l.style!.innerShadow.distance = 4; l.style!.innerShadow.blur = 0; l.style!.innerShadow.opacity = 1
        let img = try render(l)
        XCTAssertLessThan(Renderer.sample(img, at: CGPoint(x: 20, y: 11)).red, 0.1, "Light from the top: shadow inside the top edge")
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 20, y: 25)).red, 0.9)
        XCTAssertEqual(Renderer.sample(img, at: CGPoint(x: 20, y: 5)).alpha, 0, "Nothing outside")
    }

    func testInnerGlowTintsTheRim() throws {
        var l = square(); l.style = LayerStyle()
        l.style!.innerGlow.on = true; l.style!.innerGlow.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1); l.style!.innerGlow.size = 4; l.style!.innerGlow.opacity = 1
        let img = try render(l)
        XCTAssertLessThan(Renderer.sample(img, at: CGPoint(x: 10.5, y: 20)).blue, 0.6, "Red at the rim")
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 20, y: 20)).blue, 0.9, "Middle untouched")
    }

    func testGradientOverlaySpansTheLayer() throws {
        var l = square(); l.style = LayerStyle()
        l.style!.gradient.on = true; l.style!.gradient.angle = 90
        l.style!.gradient.from = CodableColor(red: 1, green: 0, blue: 0, alpha: 1); l.style!.gradient.to = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        let img = try render(l)
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 20, y: 29)).red, 0.8, "Bottom is the first colour")
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 20, y: 10)).blue, 0.8, "Top is the second colour")
        XCTAssertEqual(Renderer.sample(img, at: CGPoint(x: 5, y: 5)).alpha, 0)
    }

    func testOldStylesDecodeWithTheNewEffectsOff() throws {
        let json = Data(#"{"shadow":{"on":true,"color":{"red":0,"green":0,"blue":0,"alpha":1},"opacity":0.5,"angle":120,"distance":8,"blur":12}}"#.utf8)
        let s = try JSONDecoder().decode(LayerStyle.self, from: json)
        XCTAssertTrue(s.shadow.on); XCTAssertFalse(s.innerShadow.on); XCTAssertFalse(s.gradient.on); XCTAssertFalse(s.outline.on)
    }
}
