import XCTest
@testable import UniversePhoto

@MainActor final class BackgroundTests: XCTestCase {
    func testWhiteBackgroundUnderTheDrawingLayer() throws {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 30, height: 20, background: .white)
        XCTAssertEqual(s.layers.count, 2); XCTAssertEqual(s.selectedLayer, 1, "You draw above the background")
        let img = try XCTUnwrap(Renderer.render(layers: s.layers, width: 30, height: 20))
        let p = Renderer.sample(img, at: CGPoint(x: 29, y: 19))
        XCTAssertEqual(p.alpha, 1, accuracy: 0.01); XCTAssertEqual(p.red, 1, accuracy: 0.01)
        s.resizeCanvas(width: 60, height: 20, anchor: CGPoint(x: 0, y: 0))
        let wide = try XCTUnwrap(Renderer.render(layers: s.layers, width: 60, height: 20))
        XCTAssertEqual(Renderer.sample(wide, at: CGPoint(x: 50, y: 10)).alpha, 0, "Added canvas is transparent, as in Photoshop")
    }

    func testTransparentStaysOneLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 30, height: 20, background: nil)
        XCTAssertEqual(s.layers.count, 1); XCTAssertEqual(s.selectedLayer, 0)
    }
}
