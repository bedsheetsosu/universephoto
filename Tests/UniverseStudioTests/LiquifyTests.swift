import XCTest
@testable import UniverseStudio

@MainActor final class LiquifyTests: XCTestCase {
    /// 60×40, red block on the left half of a transparent layer.
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 60, height: 40)
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 30, y: 40, pressure: 1)]
        s.add(f)
        return s
    }
    private func alpha(_ s: Studio, _ x: Double, _ y: Double) throws -> Double {
        Renderer.sample(try XCTUnwrap(Renderer.render(layers: s.layers, width: s.width, height: s.height)), at: CGPoint(x: x, y: y)).alpha
    }
    private func push(_ s: Studio, from a: CGPoint, to b: CGPoint) {
        var stroke = InkStroke(points: [InkPoint(x: a.x, y: a.y, pressure: 1)], color: .black, width: 1)
        stroke.kind = "liquify"
        s.beginLiquify(id: stroke.id, at: a)
        for k in 1...10 { s.liquify(id: stroke.id, to: CGPoint(x: a.x + (b.x - a.x) * Double(k) / 10, y: a.y + (b.y - a.y) * Double(k) / 10)) }
        s.add(stroke)
    }

    func testPushMovesTheEdgeAlong() throws {
        let s = studio()
        s.brushSize = 30; s.toolStrength = 1
        XCTAssertEqual(try alpha(s, 34, 20), 0)
        push(s, from: CGPoint(x: 26, y: 20), to: CGPoint(x: 38, y: 20))
        XCTAssertGreaterThan(try alpha(s, 34, 20), 0.9, "Red pushed to the right")
        XCTAssertEqual(try alpha(s, 34, 2), 0, accuracy: 0.05, "Outside the brush nothing moves")
        XCTAssertGreaterThan(try alpha(s, 5, 20), 0.9, "Far pixels stay")
        XCTAssertEqual(s.undoStack.last?.label, "Liquify")
        s.undo()
        XCTAssertEqual(try alpha(s, 34, 20), 0, "Undo restores the layer")
    }

    func testNoDragChangesNothing() throws {
        let s = studio()
        let before = s.layers
        push(s, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20))
        XCTAssertEqual(try alpha(s, 29, 20), 1, accuracy: 0.01)
        XCTAssertEqual(s.layers.count, before.count)
    }
}

@MainActor final class LiquifyModeTests: XCTestCase {
    /// 80×80, a 10×10 red square in the middle (35…45).
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 80, height: 80)
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 35, y: 35, pressure: 1), InkPoint(x: 45, y: 45, pressure: 1)]
        s.add(f)
        s.brushSize = 50; s.toolStrength = 1
        return s
    }
    private func alpha(_ s: Studio, _ x: Double, _ y: Double) throws -> Double {
        Renderer.sample(try XCTUnwrap(Renderer.render(layers: s.layers, width: s.width, height: s.height)), at: CGPoint(x: x, y: y)).alpha
    }
    private func hold(_ s: Studio, _ mode: LiquifyMode, ticks: Int) {
        s.liquifyMode = mode
        var stroke = InkStroke(points: [InkPoint(x: 40, y: 40, pressure: 1)], color: .black, width: 1); stroke.kind = "liquify"
        s.beginLiquify(id: stroke.id, at: CGPoint(x: 40, y: 40))
        for _ in 0..<ticks { s.liquifyTick(id: stroke.id) }
        s.add(stroke)
    }

    func testBloatGrowsAndPuckerShrinks() throws {
        let s = studio()
        XCTAssertEqual(try alpha(s, 48, 40), 0)
        hold(s, .bloat, ticks: 30)
        XCTAssertGreaterThan(try alpha(s, 48, 40), 0.9, "Bloated past its old edge")
        s.undo()
        hold(s, .pinch, ticks: 30)
        XCTAssertEqual(try alpha(s, 43.5, 40), 0, accuracy: 0.05, "Puckered inside its old edge")
        XCTAssertGreaterThan(try alpha(s, 40, 40), 0.9)
    }

    func testTwirlTurnsCornersAndReconstructUndoesIt() throws {
        let s = studio()
        hold(s, .twirl, ticks: 10)   // ~40°: a corner points straight down
        XCTAssertGreaterThan(try alpha(s, 40, 46.5), 0.5, "A turned square reaches past its flat edge")
        // Reconstruct within one liquify session brings the displacement back to zero.
        s.liquifyMode = .twirl
        var stroke = InkStroke(points: [InkPoint(x: 40, y: 40, pressure: 1)], color: .black, width: 1); stroke.kind = "liquify"
        s.undo()
        s.beginLiquify(id: stroke.id, at: CGPoint(x: 40, y: 40))
        for _ in 0..<10 { s.liquifyTick(id: stroke.id) }
        s.liquifyMode = .reconstruct
        for _ in 0..<200 { s.liquifyTick(id: stroke.id) }
        s.add(stroke); _ = stroke
        XCTAssertEqual(try alpha(s, 40, 46.5), 0, accuracy: 0.05)
        XCTAssertGreaterThan(try alpha(s, 44, 40), 0.9)
    }
}
