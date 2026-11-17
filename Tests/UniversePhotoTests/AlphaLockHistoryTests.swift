import XCTest
@testable import UniversePhoto

@MainActor final class AlphaLockHistoryTests: XCTestCase {
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 20)
        return s
    }
    private func fill(_ s: Studio, _ c: CodableColor, x0: Double, x1: Double) {
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: c, width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: x0, y: 0, pressure: 1), InkPoint(x: x1, y: 20, pressure: 1)]
        s.add(f)
    }
    private func px(_ s: Studio, _ x: Double) throws -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let img = try XCTUnwrap(Renderer.render(layers: s.layers, width: s.width, height: s.height))
        let p = Renderer.sample(img, at: CGPoint(x: x, y: 10)); return (p.red, p.green, p.blue, p.alpha)
    }

    func testLockedTransparencyPaintsOnlyOnPixels() throws {
        let s = studio()
        fill(s, CodableColor(red: 1, green: 0, blue: 0, alpha: 1), x0: 0, x1: 20)
        s.mutateLayer("Lock transparency") { $0.lockAlpha = true }
        fill(s, CodableColor(red: 0, green: 0, blue: 1, alpha: 1), x0: 0, x1: 40)
        XCTAssertGreaterThan(try px(s, 10).blue, 0.9, "Recoloured where there were pixels")
        XCTAssertEqual(try px(s, 30).alpha, 0, "Still empty where there were none")
        s.mutateLayer("Lock transparency") { $0.lockAlpha = nil }
        fill(s, CodableColor(red: 0, green: 1, blue: 0, alpha: 1), x0: 20, x1: 40)
        XCTAssertGreaterThan(try px(s, 30).green, 0.9, "Unlocked paints everywhere again")
    }

    func testJumpingThroughHistory() throws {
        let s = studio()
        for x in [0.0, 10, 20, 30] { fill(s, CodableColor(red: 1, green: 0, blue: 0, alpha: 1), x0: x, x1: x + 10) }
        XCTAssertEqual(s.undoStack.count, 4)
        s.jumpToHistory(1)
        XCTAssertEqual(s.undoStack.count, 1); XCTAssertEqual(s.redoStack.count, 3)
        XCTAssertGreaterThan(try px(s, 5).alpha, 0.9); XCTAssertEqual(try px(s, 15).alpha, 0)
        s.jumpToHistory(3)
        XCTAssertEqual(s.undoStack.count, 3); XCTAssertGreaterThan(try px(s, 25).alpha, 0.9); XCTAssertEqual(try px(s, 35).alpha, 0)
        s.jumpToHistory(99)
        XCTAssertEqual(s.undoStack.count, 4); XCTAssertTrue(s.redoStack.isEmpty)
    }
}
