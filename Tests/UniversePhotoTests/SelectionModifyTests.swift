import XCTest
@testable import UniversePhoto

@MainActor final class SelectionModifyTests: XCTestCase {
    /// 60×60 mask with a selected 20×20 square at (20, 20).
    private let w = 60, h = 60
    private func square() -> [UInt8] {
        var m = [UInt8](repeating: 0, count: 60 * 60)
        for y in 20..<40 { for x in 20..<40 { m[y * 60 + x] = 255 } }
        return m
    }
    private func at(_ m: [UInt8], _ x: Int, _ y: Int) -> UInt8 { m[y * w + x] }

    func testRoundTripKeepsAHardMask() throws {
        let out = try XCTUnwrap(Studio.processMask(square(), width: w, height: h) { $0 })
        XCTAssertEqual(out, square())
    }

    func testExpandAndContract() throws {
        let big = try XCTUnwrap(Studio.modified(square(), width: w, height: h, .expand, radius: 5))
        XCTAssertGreaterThan(at(big, 16, 30), 200); XCTAssertEqual(at(big, 10, 30), 0)
        let small = try XCTUnwrap(Studio.modified(square(), width: w, height: h, .contract, radius: 5))
        XCTAssertEqual(at(small, 22, 30), 0); XCTAssertGreaterThan(at(small, 30, 30), 200)
    }

    func testFeatherSoftensAndSmoothStaysHard() throws {
        let soft = try XCTUnwrap(Studio.modified(square(), width: w, height: h, .feather, radius: 8))
        let edge = at(soft, 20, 30)
        XCTAssertTrue((40...215).contains(edge), "Edge is half selected, got \(edge)")
        XCTAssertGreaterThan(at(soft, 30, 30), 230)
        let smooth = try XCTUnwrap(Studio.modified(square(), width: w, height: h, .smooth, radius: 4))
        XCTAssertTrue(smooth.allSatisfy { $0 == 0 || $0 == 255 })
        XCTAssertEqual(at(smooth, 30, 30), 255)
    }

    func testBorderIsARing() throws {
        let ring = try XCTUnwrap(Studio.modified(square(), width: w, height: h, .border, radius: 6))
        XCTAssertGreaterThan(at(ring, 20, 30), 200); XCTAssertEqual(at(ring, 30, 30), 0); XCTAssertEqual(at(ring, 5, 30), 0)
    }

    func testSelectColorRangeFindsTheForegroundColour() throws {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 50, height: 40)
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: 5, y: 5, pressure: 1), InkPoint(x: 15, y: 25, pressure: 1)]
        s.add(f)
        s.color = CodableColor(red: 0.95, green: 0.05, blue: 0, alpha: 1); s.tolerance = 32
        s.selectColorRange()
        XCTAssertEqual(try XCTUnwrap(s.selection).bounds, CGRect(x: 5, y: 5, width: 10, height: 20))
        s.color = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        s.selectColorRange()
        XCTAssertNil(s.selection)
    }
}
