import XCTest
@testable import TafelKit

final class PaletteGridTests: XCTestCase {
    func testColumnsAndSize() {
        XCTAssertEqual(PaletteGridLayout.columns(count: 6), 3)
        XCTAssertEqual(PaletteGridLayout.rows(count: 6), 2)
        XCTAssertEqual(PaletteGridLayout.columns(count: 12), 4)
        XCTAssertEqual(PaletteGridLayout.rows(count: 4), 1)
        let s = PaletteGridLayout.size(count: 6)
        XCTAssertEqual(s.width, 12 * 2 + 3 * 58 + 2 * 8)
    }

    func testCentresMapBackAndGapsAreEmpty() {
        for n in 2...12 {
            for i in 0..<n {
                let c = PaletteGridLayout.center(of: i, count: n)
                XCTAssertEqual(PaletteGridLayout.item(x: c.x, y: c.y, count: n), i, "n=\(n) i=\(i)")
            }
        }
        let a = PaletteGridLayout.center(of: 0, count: 6)
        XCTAssertNil(PaletteGridLayout.item(x: a.x + 58 / 2 + 4, y: a.y, count: 6))   // in the gap
        XCTAssertNil(PaletteGridLayout.item(x: 5, y: 5, count: 6))                      // header
        XCTAssertNil(PaletteGridLayout.item(x: PaletteGridLayout.center(of: 2, count: 5).x, y: PaletteGridLayout.center(of: 4, count: 5).y, count: 5)) // empty cell
    }

    func testPanelStaysOnScreen() {
        let s = PaletteGridLayout.size(count: 6)
        let mid = PaletteGridLayout.origin(tipX: 600, tipY: 500, width: 1180, height: 820, count: 6)
        XCTAssertEqual(mid.y + s.height, 500 - PaletteGridLayout.tipGap, accuracy: 1e-9)   // above the tip
        let top = PaletteGridLayout.origin(tipX: 600, tipY: 40, width: 1180, height: 820, count: 6)
        XCTAssertEqual(top.y, 40 + PaletteGridLayout.tipGap, accuracy: 1e-9)                // below near the top
        let corner = PaletteGridLayout.origin(tipX: 1175, tipY: 10, width: 1180, height: 820, count: 6)
        XCTAssertLessThanOrEqual(corner.x + s.width, 1180 - 12 + 1e-9)
        XCTAssertGreaterThanOrEqual(corner.x, 12)
    }
}
