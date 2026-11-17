import XCTest
@testable import UniversePhoto

@MainActor final class ImageMenuTests: XCTestCase {
    /// 100×80 document with a black 20×10 block at (10, 10).
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 80)
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .black, width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 10, y: 10, pressure: 1), InkPoint(x: 30, y: 20, pressure: 1)]
        s.add(f)
        return s
    }
    private func box(_ s: Studio) -> CGRect? { s.contentBounds(s.layers[s.selectedLayer]) }
    private func alpha(_ s: Studio, _ x: Double, _ y: Double) throws -> Double {
        Renderer.sample(try XCTUnwrap(Renderer.render(layers: s.layers, width: s.width, height: s.height)), at: CGPoint(x: x, y: y)).alpha
    }

    func testImageSizeScalesEverything() throws {
        let s = studio()
        s.resizeImage(width: 200, height: 160)
        XCTAssertEqual(s.width, 200); XCTAssertEqual(s.height, 160)
        let b = try XCTUnwrap(box(s))
        XCTAssertEqual(b.midX, 40, accuracy: 0.5); XCTAssertEqual(b.width, 40, accuracy: 2.5, "Smooth resampling softens one pixel per edge"); XCTAssertEqual(b.height, 20, accuracy: 2.5)
        s.undo()
        XCTAssertEqual(s.width, 100); XCTAssertEqual(box(s), CGRect(x: 10, y: 10, width: 20, height: 10))
    }

    func testCanvasSizeKeepsPixelsAtTheAnchor() throws {
        let s = studio()
        s.resizeCanvas(width: 140, height: 100, anchor: CGPoint(x: 1, y: 1))
        XCTAssertEqual(box(s), CGRect(x: 50, y: 30, width: 20, height: 10))
    }

    func testCropToSelectionAndTrim() throws {
        let s = studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 5, y: 5), CGPoint(x: 45, y: 35)])
        s.cropToSelection()
        XCTAssertEqual(s.width, 40); XCTAssertEqual(s.height, 30); XCTAssertNil(s.selection)
        XCTAssertEqual(box(s), CGRect(x: 5, y: 5, width: 20, height: 10))
        s.trim()
        XCTAssertEqual(s.width, 20); XCTAssertEqual(s.height, 10)
    }

    func testRotateClockwiseMovesTopLeftToTopRight() throws {
        let s = studio()
        s.rotateCanvas(.clockwise)
        XCTAssertEqual(s.width, 80); XCTAssertEqual(s.height, 100)
        XCTAssertEqual(box(s), CGRect(x: 60, y: 10, width: 10, height: 20))
        s.rotateCanvas(.counterClockwise)
        XCTAssertEqual(box(s), CGRect(x: 10, y: 10, width: 20, height: 10))
        s.rotateCanvas(.halfTurn)
        XCTAssertEqual(box(s), CGRect(x: 70, y: 60, width: 20, height: 10))
    }

    func testFlipCanvasAndLayer() throws {
        let s = studio()
        s.flipCanvas(horizontal: true)
        XCTAssertEqual(box(s), CGRect(x: 70, y: 10, width: 20, height: 10))
        s.flipLayer(horizontal: false)
        XCTAssertEqual(box(s), CGRect(x: 70, y: 60, width: 20, height: 10))
    }

    func testEveryFrameChangesWithTheDocument() throws {
        let s = studio()
        s.addFrame()
        s.rotateCanvas(.clockwise)
        XCTAssertEqual(s.frames.count, 2)
        for frame in s.frames { XCTAssertEqual(s.contentBounds(frame[0]), CGRect(x: 60, y: 10, width: 10, height: 20)) }
    }

    func testMaskFromSelectionRevealsOrHides() throws {
        let s = studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)])
        s.maskFromSelection(reveal: true)
        XCTAssertGreaterThan(try alpha(s, 15, 15), 0.9)
        XCTAssertEqual(try alpha(s, 25, 15), 0, accuracy: 0.01)
        s.maskFromSelection(reveal: false)
        XCTAssertEqual(try alpha(s, 15, 15), 0, accuracy: 0.01)
        XCTAssertGreaterThan(try alpha(s, 25, 15), 0.9)
    }
}
