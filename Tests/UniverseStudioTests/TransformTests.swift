import XCTest
@testable import UniverseStudio

@MainActor final class TransformTests: XCTestCase {
    /// 100×80 document with a 20×10 block at (10, 10).
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 80)
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .black, width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 10, y: 10, pressure: 1), InkPoint(x: 30, y: 20, pressure: 1)]
        s.add(f)
        return s
    }
    private func centre(_ c: [CGPoint]) -> CGPoint { CGPoint(x: c.map(\.x).reduce(0, +) / 4, y: c.map(\.y).reduce(0, +) / 4) }

    func testContentBoundsFindThePixels() throws {
        let s = studio()
        XCTAssertEqual(s.contentBounds(try XCTUnwrap(s.activeLayer)), CGRect(x: 10, y: 10, width: 20, height: 10))
        XCTAssertNil(s.contentBounds(ArtLayer(name: "empty")))
    }

    func testScaleAndRotateKeepTheContentCentre() throws {
        let s = studio()
        let before = centre(try XCTUnwrap(s.transformCorners()))
        s.layers[0].transform = s.transformKeepingCentre(from: s.layers[0].transform, scale: 2.5, rotation: 30)
        let corners = try XCTUnwrap(s.transformCorners())
        let after = centre(corners)
        XCTAssertEqual(after.x, before.x, accuracy: 0.001); XCTAssertEqual(after.y, before.y, accuracy: 0.001)
        XCTAssertEqual(hypot(corners[1].x - corners[0].x, corners[1].y - corners[0].y), 50, accuracy: 0.001, "Width 20 × 2.5")
        XCTAssertEqual(atan2(corners[1].y - corners[0].y, corners[1].x - corners[0].x) * 180 / .pi, 30, accuracy: 0.001)
    }

    func testAlignToCanvasEdgesAndCentre() throws {
        let s = studio()
        s.align(.right)
        XCTAssertEqual(try XCTUnwrap(s.transformCorners()).map(\.x).max()!, 100, accuracy: 0.001)
        s.align(.centerY)
        let c = try XCTUnwrap(s.transformCorners())
        XCTAssertEqual((c.map(\.y).min()! + c.map(\.y).max()!) / 2, 40, accuracy: 0.001)
        s.undo(); s.undo()
        XCTAssertEqual(s.layers[0].transform, LayerTransform())
    }

    func testTextKeepsItsFontAndOldTextStaysHelvetica() throws {
        var t = InkStroke(points: [InkPoint(x: 5, y: 5, pressure: 1)], color: .black, width: 20)
        t.kind = "text"; t.text = "Hi"; t.fontName = "Georgia-Bold"
        let back = try JSONDecoder().decode(InkStroke.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back.fontName, "Georgia-Bold")
        var layer = ArtLayer(name: "t"); layer.strokes = [back]
        XCTAssertNotNil(Renderer.render(layers: [layer], width: 60, height: 40))
        let old = #"{"id":"6E1B2B53-2F43-4E0B-9C59-6D6A1D4D3B11","points":[{"x":1,"y":1,"pressure":1}],"color":{"red":0,"green":0,"blue":0,"alpha":1},"width":12,"isEraser":false,"kind":"text","text":"x"}"#
        XCTAssertNil(try JSONDecoder().decode(InkStroke.self, from: Data(old.utf8)).fontName)
    }
}
