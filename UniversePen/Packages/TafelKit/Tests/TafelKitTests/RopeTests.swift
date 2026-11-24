import XCTest
import CoreGraphics
@testable import TafelKit

final class RopeTests: XCTestCase {
    func testJitterInsideTheRopeIsIgnored() {
        var r = Rope(length: 20)
        _ = r.start(at: .zero)
        XCTAssertEqual(r.pull(to: CGPoint(x: 10, y: 5)), .zero)
        XCTAssertEqual(r.pull(to: CGPoint(x: -8, y: 12)), .zero)
    }

    func testPullKeepsTheRopeLength() {
        var r = Rope(length: 20)
        _ = r.start(at: .zero)
        let p = r.pull(to: CGPoint(x: 50, y: 0))
        XCTAssertEqual(p.x, 30, accuracy: 0.0001)
        XCTAssertEqual(p.y, 0, accuracy: 0.0001)
    }
}
