import XCTest
@testable import TafelKit

final class RulerTests: XCTestCase {
    func testHorizontalRulerSnapsToNearerEdge() throws {
        let r = Ruler(center: CGPoint(x: 500, y: 400))
        let below = try XCTUnwrap(r.snapLine(for: CGPoint(x: 300, y: 450)))   // 8 pt below the lower edge
        XCTAssertEqual(below.project(CGPoint(x: 700, y: 470)).y, 400 + 42 + 2, accuracy: 1e-9)
        XCTAssertEqual(below.project(CGPoint(x: 700, y: 470)).x, 700, accuracy: 1e-9)
        let above = try XCTUnwrap(r.snapLine(for: CGPoint(x: 300, y: 370)))   // on the ruler, upper half
        XCTAssertEqual(above.project(CGPoint(x: 10, y: 0)).y, 400 - 44, accuracy: 1e-9)
        XCTAssertNil(r.snapLine(for: CGPoint(x: 300, y: 600)))               // far away: free stroke
    }

    func testRotatedRulerKeepsStrokesOnItsLine() throws {
        let r = Ruler(center: CGPoint(x: 0, y: 0), angle: .pi / 4)
        XCTAssertTrue(r.contains(CGPoint(x: 100, y: 100)))
        XCTAssertFalse(r.contains(CGPoint(x: 100, y: -100)))
        let line = try XCTUnwrap(r.snapLine(for: CGPoint(x: 60, y: 120)))
        let a = line.project(CGPoint(x: 300, y: 200)), b = line.project(CGPoint(x: -50, y: 10))
        XCTAssertEqual((a.y - b.y) / (a.x - b.x), 1, accuracy: 1e-9)          // still 45°
    }

    func testAngleSnapsToFortyFive() {
        XCTAssertEqual(Ruler.snapped(44.2 * .pi / 180), .pi / 4, accuracy: 1e-9)
        XCTAssertEqual(Ruler.snapped(40 * .pi / 180), 40 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(Ruler(center: .zero, angle: -.pi / 2).degrees, 90)
    }

    func testPressurePresetsAreMonotone() {
        for p in PressureCurve.Preset.allCases {
            var c = PressureCurve()
            c.apply(p)
            var last = -1.0
            for i in 0...20 {
                let v = c.map(Double(i) / 20)
                XCTAssertGreaterThanOrEqual(v, last - 1e-9, "\(p)")
                last = v
            }
            XCTAssertEqual(c.map(1), 1, accuracy: 1e-9)
        }
    }
}
