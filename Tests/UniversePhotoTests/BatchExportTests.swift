import XCTest
import ImageIO
@testable import UniversePhoto

@MainActor final class BatchExportTests: XCTestCase {
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 30, background: .white)
        s.layers[1].name = "Ink/Line: 1"
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 10, y: 10, pressure: 1), InkPoint(x: 20, y: 20, pressure: 1)]
        s.add(f)
        s.newLayer(); s.layers[2].name = "Hidden sketch"; s.layers[2].visible = false
        s.newAdjustmentLayer()
        return s
    }

    func testEachVisiblePixelLayerBecomesAPNG() throws {
        let s = studio()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = try s.exportLayers(to: dir)
        XCTAssertEqual(files.map(\.lastPathComponent), ["01 Background.png", "02 Ink-Line- 1.png"])
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(files[1] as CFURL, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 40)
        XCTAssertEqual(Renderer.sample(img, at: CGPoint(x: 5, y: 5)).alpha, 0, "Only the layer itself, no background")
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 15, y: 15)).red, 0.9)
        XCTAssertEqual(try s.exportLayers(to: dir, onlyVisible: false).count, 3, "Hidden too; adjustment layers never")
    }

    func testSelectionImageIsCroppedAndMasked() throws {
        let s = studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 15)], ellipse: true)
        let img = try XCTUnwrap(s.selectionImage())
        XCTAssertEqual(img.width, 20); XCTAssertEqual(img.height, 10)
        XCTAssertEqual(Renderer.sample(img, at: CGPoint(x: 0.5, y: 0.5)).alpha, 0, "Outside the ellipse")
        XCTAssertGreaterThan(Renderer.sample(img, at: CGPoint(x: 10, y: 5)).alpha, 0.9)
    }

    func testLayerSearch() {
        let s = studio()
        XCTAssertEqual(s.layerMatches("ink"), [1])
        XCTAssertEqual(s.layerMatches("hidden"), [2])
        XCTAssertEqual(s.layerMatches("adj"), [3])
        XCTAssertEqual(s.layerMatches("").count, 4)
        XCTAssertEqual(s.layerMatches("zzz"), [])
        XCTAssertEqual(Studio.fileName("  "), "Layer")
    }
}
