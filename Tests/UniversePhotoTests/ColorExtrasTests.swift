import XCTest
@testable import UniversePhoto

@MainActor final class ColorExtrasTests: XCTestCase {
    func testHexRoundTripAndShortForms() throws {
        let c = try XCTUnwrap(CodableColor(hex: "#7FE3D3"))
        XCTAssertEqual(c.hex, "#7FE3D3"); XCTAssertEqual(c.alpha, 1)
        XCTAssertEqual(CodableColor(hex: "f00")?.hex, "#FF0000")
        XCTAssertEqual(try XCTUnwrap(CodableColor(hex: "00000080")).alpha, 128.0 / 255, accuracy: 0.001)
        XCTAssertNil(CodableColor(hex: "nope")); XCTAssertNil(CodableColor(hex: "#12345"))
    }

    func testHarmoniesTurnTheHue() {
        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        XCTAssertEqual(red.rotated(180).hex, "#00FFFF")
        XCTAssertEqual(red.rotated(120).hex, "#00FF00")
        XCTAssertEqual(red.rotated(-120).hex, "#0000FF")
        XCTAssertEqual(red.rotated(180).alpha, 0.5)
        XCTAssertEqual(red.harmonies.count, 5)
    }

    func testSwapAndRecentColors() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 20, height: 20)
        s.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1); s.secondaryColor = .white
        s.swapColors()
        XCTAssertEqual(s.color, .white); XCTAssertEqual(s.secondaryColor.hex, "#FF0000")
        for i in 0..<12 {
            var f = InkStroke(points: [InkPoint(x: 1, y: 1, pressure: 1)], color: CodableColor(red: Double(i) / 20, green: 0, blue: 0, alpha: 0.4), width: 4)
            f.kind = nil
            s.add(f)
        }
        s.add(InkStroke(points: [InkPoint(x: 1, y: 1, pressure: 1)], color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), width: 4))
        s.add(InkStroke(points: [InkPoint(x: 1, y: 1, pressure: 1)], color: CodableColor(red: 11.0 / 20, green: 0, blue: 0, alpha: 1), width: 4))
        XCTAssertEqual(s.recentColors.count, 10)
        XCTAssertEqual(s.recentColors.first?.hex, CodableColor(red: 11.0 / 20, green: 0, blue: 0, alpha: 1).hex, "Most recent first, no duplicates")
        XCTAssertEqual(Set(s.recentColors.map(\.hex)).count, 10)
        XCTAssertEqual(s.recentColors.first?.alpha, 1)
    }
}
