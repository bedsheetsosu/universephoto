import XCTest
import AppKit
@testable import UniverseStudio

final class SelectionClippingCurvesTests: XCTestCase {
    private func filled(_ rect: CGRect, _ color: CodableColor) -> InkStroke {
        var s = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: color, width: 1)
        s.kind = "fill"
        s.selectionPoints = [InkPoint(x: rect.minX, y: rect.minY, pressure: 1), InkPoint(x: rect.maxX, y: rect.maxY, pressure: 1)]
        return s
    }
    private let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1), blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)

    func testClippedLayerOnlyShowsOverItsBase() throws {
        var base = ArtLayer(name: "base"); base.strokes = [filled(CGRect(x: 0, y: 0, width: 10, height: 20), red)]
        var top = ArtLayer(name: "top"); top.strokes = [filled(CGRect(x: 0, y: 0, width: 20, height: 20), blue)]; top.clipped = true
        let image = try XCTUnwrap(Renderer.render(layers: [base, top], width: 20, height: 20))
        XCTAssertGreaterThan(Renderer.sample(image, at: CGPoint(x: 5, y: 10)).blue, 0.9, "Blue over the base")
        XCTAssertEqual(Renderer.sample(image, at: CGPoint(x: 15, y: 10)).alpha, 0, "Nothing outside the base")
        base.visible = false
        let hidden = try XCTUnwrap(Renderer.render(layers: [base, top], width: 20, height: 20))
        XCTAssertEqual(Renderer.sample(hidden, at: CGPoint(x: 5, y: 10)).alpha, 0, "A hidden base hides its clipped layers")
        top.clipped = false
        let free = try XCTUnwrap(Renderer.render(layers: [base, top], width: 20, height: 20))
        XCTAssertGreaterThan(Renderer.sample(free, at: CGPoint(x: 15, y: 10)).blue, 0.9)
    }

    func testClippingFollowsAMovedBase() throws {
        var base = ArtLayer(name: "base"); base.strokes = [filled(CGRect(x: 0, y: 0, width: 10, height: 20), red)]; base.transform.x = 10
        var top = ArtLayer(name: "top"); top.strokes = [filled(CGRect(x: 0, y: 0, width: 20, height: 20), blue)]; top.clipped = true
        let image = try XCTUnwrap(Renderer.render(layers: [base, top], width: 20, height: 20))
        XCTAssertEqual(Renderer.sample(image, at: CGPoint(x: 5, y: 10)).alpha, 0)
        XCTAssertGreaterThan(Renderer.sample(image, at: CGPoint(x: 15, y: 10)).blue, 0.9)
    }

    func testOlderLayersAreNotClipped() throws {
        let json = #"{"name":"old","visible":true,"strokes":[],"opacity":1,"blend":"normal","locked":false}"#
        XCTAssertFalse(try JSONDecoder().decode(ArtLayer.self, from: Data(json.utf8)).clipped)
    }

    func testCurveInterpolationIsMonotoneAndHitsItsPoints() {
        let pts = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.5), CurvePoint(x: 0.5, y: 0.55), CurvePoint(x: 1, y: 1)]
        XCTAssertEqual(ToneCurve.evaluate(pts, at: 0.25), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ToneCurve.evaluate(pts, at: 0.5), 0.55, accuracy: 1e-9)
        var last = -1.0
        for i in 0...200 { let v = ToneCurve.evaluate(pts, at: Double(i) / 200); XCTAssertGreaterThanOrEqual(v, last - 1e-9); last = v }
        XCTAssertNil(ToneCurve.table(["rgb": ToneCurve.identity]), "A straight curve costs nothing")
        XCTAssertEqual(ToneCurve.table(["rgb": pts])?.count, 256 * 3 * 4)
    }

    func testCurvesChangeTheRenderedPixels() throws {
        var layer = ArtLayer(name: "grey")
        layer.strokes = [filled(CGRect(x: 0, y: 0, width: 8, height: 8), CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))]
        let before = Renderer.sample(try XCTUnwrap(Renderer.render(layers: [layer], width: 8, height: 8)), at: CGPoint(x: 4, y: 4))
        layer.adjustment.curves = ["red": [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.9), CurvePoint(x: 1, y: 1)]]
        let after = Renderer.sample(try XCTUnwrap(Renderer.render(layers: [layer], width: 8, height: 8)), at: CGPoint(x: 4, y: 4))
        XCTAssertGreaterThan(after.red, before.red + 0.2, "The red curve lifts red")
        XCTAssertEqual(after.green, before.green, accuracy: 0.03, "Green stays")
    }

    @MainActor func testCopyPasteInPlaceAndCut() throws {
        let studio = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        studio.pasteboard = NSPasteboard(name: NSPasteboard.Name("UniverseStudioTests-\(UUID().uuidString)"))
        defer { studio.pasteboard.releaseGlobally() }
        studio.newDocument(width: 20, height: 20)
        studio.add(filled(CGRect(x: 0, y: 0, width: 20, height: 20), red))
        studio.selection = CanvasSelection(points: [CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 10)])
        studio.copySelection()
        studio.paste()
        XCTAssertEqual(studio.layers.count, 2)
        let pasted = try XCTUnwrap(Renderer.render(layers: [studio.layers[1]], width: 20, height: 20))
        XCTAssertGreaterThan(Renderer.sample(pasted, at: CGPoint(x: 7, y: 7)).alpha, 0.9, "Pasted where it was copied")
        XCTAssertEqual(Renderer.sample(pasted, at: CGPoint(x: 15, y: 15)).alpha, 0)
        studio.selectedLayer = 0
        studio.cutSelection()
        let source = try XCTUnwrap(Renderer.render(layers: [studio.layers[0]], width: 20, height: 20))
        XCTAssertEqual(Renderer.sample(source, at: CGPoint(x: 7, y: 7)).alpha, 0, "Cut leaves a hole")
        XCTAssertGreaterThan(Renderer.sample(source, at: CGPoint(x: 15, y: 15)).alpha, 0.9)
    }

    @MainActor func testLayerViaCutMovesPixelsToANewLayer() throws {
        let studio = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        studio.newDocument(width: 20, height: 20)
        studio.add(filled(CGRect(x: 0, y: 0, width: 20, height: 20), red))
        studio.selection = CanvasSelection(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 20)])
        studio.layerFromSelection(cut: true)
        XCTAssertEqual(studio.layers.count, 2); XCTAssertEqual(studio.selectedLayer, 1); XCTAssertNil(studio.selection)
        let composite = try XCTUnwrap(Renderer.render(layers: studio.layers, width: 20, height: 20))
        XCTAssertGreaterThan(Renderer.sample(composite, at: CGPoint(x: 5, y: 10)).red, 0.9, "Nothing is lost")
        let lower = try XCTUnwrap(Renderer.render(layers: [studio.layers[0]], width: 20, height: 20))
        XCTAssertEqual(Renderer.sample(lower, at: CGPoint(x: 5, y: 10)).alpha, 0)
        studio.undo()
        XCTAssertEqual(studio.layers.count, 1, "One undo step")
    }
}
