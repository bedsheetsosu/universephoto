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
