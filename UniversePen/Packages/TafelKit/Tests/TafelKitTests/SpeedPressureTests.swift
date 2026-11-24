import XCTest
@testable import TafelKit

final class SpeedPressureTests: XCTestCase {
    func testSlowKeepsPressureFastLightens() {
        XCTAssertEqual(SpeedPressure.apply(0.8, speed: 0, amount: 1), 0.8, accuracy: 1e-9)
        XCTAssertEqual(SpeedPressure.apply(0.8, speed: 5000, amount: 1), 0.2, accuracy: 1e-9)
        XCTAssertEqual(SpeedPressure.apply(0.8, speed: 5000, amount: 0), 0.8, accuracy: 1e-9)
        let mid = SpeedPressure.apply(0.8, speed: 1250, amount: 1)
        XCTAssertLessThan(mid, 0.8); XCTAssertGreaterThan(mid, 0.2)
    }
}
