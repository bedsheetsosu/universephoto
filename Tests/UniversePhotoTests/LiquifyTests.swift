import XCTest
@testable import UniversePhoto

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
