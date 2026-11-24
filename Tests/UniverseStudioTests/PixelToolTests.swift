import XCTest
import CoreGraphics
@testable import UniverseStudio

final class PixelToolTests: XCTestCase {
    /// 10×10 transparent picture with an opaque red 4×4 square at (2,2) and a separate red pixel at (8,8).
    private func picture() -> PixelOps.Bitmap {
        var b = PixelOps.Bitmap(width: 10, height: 10, bytes: [UInt8](repeating: 0, count: 400))
        func red(_ x: Int, _ y: Int) { let i = b.index(x, y); b.bytes[i] = 255; b.bytes[i + 3] = 255 }
        for y in 2..<6 { for x in 2..<6 { red(x, y) } }
        red(8, 8)
        return b
    }

    func testContiguousFillStaysInsideTheConnectedRegion() {
        let mask = PixelOps.similarRegion(in: picture(), seed: (3, 3), tolerance: 0, contiguous: true)
        XCTAssertEqual(mask.filter { $0 != 0 }.count, 16)
        XCTAssertEqual(mask[8 * 10 + 8], 0, "The separate pixel is not connected")
    }

    func testNonContiguousFindsEverySimilarPixel() {
        let mask = PixelOps.similarRegion(in: picture(), seed: (3, 3), tolerance: 0, contiguous: false)
        XCTAssertEqual(mask.filter { $0 != 0 }.count, 17)
    }

    func testToleranceDecidesWhatCountsAsSimilar() {
        var b = picture()
        let i = b.index(4, 4); b.bytes[i] = 200            // a slightly darker red inside the square
        XCTAssertEqual(PixelOps.similarRegion(in: b, seed: (3, 3), tolerance: 10, contiguous: true).filter { $0 != 0 }.count, 15)
        XCTAssertEqual(PixelOps.similarRegion(in: b, seed: (3, 3), tolerance: 60, contiguous: true).filter { $0 != 0 }.count, 16)
    }

    func testFillOfTransparentAreaAroundAShape() {
        let mask = PixelOps.similarRegion(in: picture(), seed: (0, 0), tolerance: 0, contiguous: true)
        XCTAssertEqual(mask.filter { $0 != 0 }.count, 100 - 17)
    }

    func testGrowCoversTheEdgePixels() {
        var mask = [UInt8](repeating: 0, count: 25); mask[12] = 255
        XCTAssertEqual(PixelOps.grow(mask, width: 5, height: 5).filter { $0 != 0 }.count, 5)
    }

    func testMaskBoundsAndGrayRoundTrip() throws {
        let mask = PixelOps.similarRegion(in: picture(), seed: (3, 3), tolerance: 0, contiguous: true)
        XCTAssertEqual(PixelOps.bounds(mask, width: 10, height: 10), CGRect(x: 2, y: 2, width: 4, height: 4))
        let image = try XCTUnwrap(PixelOps.grayImage(mask, width: 10, height: 10))
        XCTAssertEqual(PixelOps.grayBytes(image), mask, "Row 0 stays the top row")
        let decoded = try XCTUnwrap(PixelOps.decodeGray(try XCTUnwrap(PixelOps.png(image))))
        XCTAssertEqual(PixelOps.grayBytes(decoded), mask)
    }

    @MainActor func testBucketStrokeRendersOnlyTheRegion() throws {
        let studio = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        studio.newDocument(width: 40, height: 30)
        studio.color = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        // A black box outline splits inside from outside.
        var box = InkStroke(points: [InkPoint(x: 10, y: 10, pressure: 1), InkPoint(x: 30, y: 20, pressure: 1)], color: .black, width: 2)
        box.kind = "rectangle"
        studio.add(box)
        let fill = try XCTUnwrap(studio.bucketStroke(at: CGPoint(x: 20, y: 15), documentPoint: CGPoint(x: 20, y: 15)))
        studio.add(fill)
        let image = try XCTUnwrap(Renderer.render(layers: studio.layers, width: 40, height: 30))
        let inside = Renderer.sample(image, at: CGPoint(x: 20, y: 15)), outside = Renderer.sample(image, at: CGPoint(x: 3, y: 3))
        XCTAssertGreaterThan(inside.blue, 0.9); XCTAssertGreaterThan(inside.alpha, 0.9)
        XCTAssertEqual(outside.alpha, 0, "Outside the box stays transparent")
        studio.undo()
        XCTAssertEqual(studio.layers[0].strokes.count, 1, "The fill is one undo step")
    }

    @MainActor func testMagicWandSelectsAddsAndSubtracts() throws {
        let studio = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        studio.newDocument(width: 20, height: 20)
        var square = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .black, width: 1)
        square.kind = "fill"; square.selectionPoints = [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 10, y: 10, pressure: 1)]
        studio.add(square)
        studio.tolerance = 0
        studio.magicWand(at: CGPoint(x: 5, y: 5), combine: .replace)
        let selected = try XCTUnwrap(studio.selectionMask())
        XCTAssertEqual(selected.filter { $0 != 0 }.count, 100)
        studio.magicWand(at: CGPoint(x: 15, y: 15), combine: .add)
        XCTAssertEqual(try XCTUnwrap(studio.selectionMask()).filter { $0 != 0 }.count, 400)
        studio.magicWand(at: CGPoint(x: 5, y: 5), combine: .subtract)
        XCTAssertEqual(try XCTUnwrap(studio.selectionMask()).filter { $0 != 0 }.count, 300)
    }

    @MainActor func testInvertSelectionAndStrokesClipToTheMask() throws {
        let studio = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        studio.newDocument(width: 20, height: 20)
        studio.selection = CanvasSelection(points: [.zero, CGPoint(x: 10, y: 20)])   // left half
        studio.invertSelection()                                                       // → right half
        let mask = try XCTUnwrap(studio.selectionMask())
        XCTAssertEqual(mask[5 * 20 + 2], 0); XCTAssertEqual(mask[5 * 20 + 15], 255)
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1)
        fill.kind = "fill"; fill.selectionMask = studio.selection?.maskData
        studio.add(fill)
        let image = try XCTUnwrap(Renderer.render(layers: studio.layers, width: 20, height: 20))
        XCTAssertEqual(Renderer.sample(image, at: CGPoint(x: 3, y: 10)).alpha, 0)
        XCTAssertGreaterThan(Renderer.sample(image, at: CGPoint(x: 16, y: 10)).red, 0.9)
    }

    func testOlderAdjustmentsDecodeWithNeutralNewValues() throws {
        let json = #"{"brightness":0.1,"contrast":1,"saturation":1,"exposure":0,"blur":0,"inverted":false}"#
        let a = try JSONDecoder().decode(LayerAdjustment.self, from: Data(json.utf8))
        XCTAssertEqual(a.brightness, 0.1)
        XCTAssertEqual(a.levelsWhite, 1); XCTAssertEqual(a.gamma, 1); XCTAssertEqual(a.hue, 0)
        var b = a; b.brightness = 0
        XCTAssertEqual(b, LayerAdjustment(), "Neutral new values keep the fast path")
    }

    func testEveryLookAndEveryBlendModeRenders() throws {
        var layer = ArtLayer(name: "L")
        var dot = InkStroke(points: [InkPoint(x: 8, y: 8, pressure: 1)], color: CodableColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1), width: 10)
        dot.kind = nil
        layer.strokes = [dot]
        for look in AdjustmentLook.allCases {
            look.apply(to: &layer.adjustment)
            XCTAssertNotNil(Renderer.render(layers: [layer], width: 16, height: 16), "\(look)")
        }
        layer.adjustment = .init()
        for blend in LayerBlend.allCases {
            layer.blend = blend
            XCTAssertNotNil(Renderer.render(layers: [ArtLayer(name: "base"), layer], width: 16, height: 16), "\(blend)")
        }
    }
}
