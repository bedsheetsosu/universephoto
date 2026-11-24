import XCTest
@testable import UniverseStudio

@MainActor final class AdjustmentLayerTests: XCTestCase {
    /// Left half red, right half blue, then an adjustment layer on top.
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 20)
        for (c, x) in [(CodableColor(red: 1, green: 0, blue: 0, alpha: 1), 0.0), (CodableColor(red: 0, green: 0, blue: 1, alpha: 1), 20.0)] {
            var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: c, width: 1)
            f.kind = "fill"; f.selectionPoints = [InkPoint(x: x, y: 0, pressure: 1), InkPoint(x: x + 20, y: 20, pressure: 1)]
            s.add(f)
        }
        s.newAdjustmentLayer()
        return s
    }
    private func px(_ s: Studio, _ x: Double) throws -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let img = try XCTUnwrap(Renderer.render(layers: s.composite(s.layers), width: s.width, height: s.height))
        let p = Renderer.sample(img, at: CGPoint(x: x, y: 10)); return (p.red, p.green, p.blue, p.alpha)
    }

    func testAdjustsEverythingBelow() throws {
        let s = studio()
        XCTAssertTrue(try XCTUnwrap(s.activeLayer).isAdjustmentLayer)
        s.mutateLayer("Saturation") { $0.adjustment.saturation = 0 }
        let left = try px(s, 5), right = try px(s, 35)
        XCTAssertEqual(left.red, left.blue, accuracy: 0.03, "Grey"); XCTAssertEqual(right.red, right.blue, accuracy: 0.03)
        XCTAssertEqual(left.alpha, 1, accuracy: 0.01)
    }

    func testOpacityAndMaskLimitTheEffect() throws {
        let s = studio()
        s.mutateLayer("Invert") { $0.adjustment.inverted = true }
        XCTAssertGreaterThan(try px(s, 5).green, 0.9, "Red inverted is cyan")
        // Painting on an adjustment layer paints its mask: hide the effect on the left half.
        var hide = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), width: 1)
        hide.kind = "fill"; hide.selectionPoints = [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 20, y: 20, pressure: 1)]
        s.add(hide)
        XCTAssertTrue(try XCTUnwrap(s.activeLayer).strokes.isEmpty)
        XCTAssertGreaterThan(try px(s, 5).red, 0.9, "Masked: original red")
        XCTAssertGreaterThan(try px(s, 35).red, 0.9, "Blue inverted is yellow")
        s.mutateLayer("Opacity") { $0.opacity = 0.5 }
        XCTAssertEqual(try px(s, 35).blue, 0.5, accuracy: 0.05)
    }

    func testLayersAboveAreNotAffectedAndOldFilesHaveNone() throws {
        let s = studio()
        s.mutateLayer("Saturation") { $0.adjustment.saturation = 0 }
        s.newLayer()
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 0, green: 1, blue: 0, alpha: 1), width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 10, y: 20, pressure: 1)]
        s.add(f)
        XCTAssertGreaterThan(try px(s, 5).green, 0.9)
        let old = try JSONDecoder().decode(ArtLayer.self, from: Data(#"{"name":"old"}"#.utf8))
        XCTAssertFalse(old.isAdjustmentLayer)
    }
}
