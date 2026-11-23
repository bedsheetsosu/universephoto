import XCTest
@testable import TafelKit

final class TwoFingerLockTests: XCTestCase {
    func testPinchWithDriftingFingersOnlyZooms() {
        var lock = TwoFingerLock()
        // A real pinch: the distance grows, the centre wanders a few points.
        for i in 1...30 {
            lock.pan(translation: Double(i % 5) * 2)          // jitter up to 8 pt
            lock.pinch(scale: 1 + Double(i) * 0.01)
        }
        XCTAssertEqual(lock.mode, .zoom)
        lock.pan(translation: 80)                               // even a big drift later stays zoom
        XCTAssertEqual(lock.mode, .zoom)
    }

    func testScrollWithBreathingFingersOnlyScrolls() {
        var lock = TwoFingerLock()
        for i in 1...20 { lock.pinch(scale: 1 + (i % 2 == 0 ? 0.02 : -0.02)); lock.pan(translation: Double(i) * 2) }
        XCTAssertEqual(lock.mode, .scroll)
        lock.pinch(scale: 1.5)
        XCTAssertEqual(lock.mode, .scroll)
    }

    func testUndecidedUntilAThresholdAndResetForTheNextTouch() {
        var lock = TwoFingerLock()
        lock.pan(translation: 5); lock.pinch(scale: 1.03)
        XCTAssertEqual(lock.mode, .undecided, "Small movements send nothing yet")
        lock.pinch(scale: 0.9)                                  // pinching in counts the same
        XCTAssertEqual(lock.mode, .zoom)
        lock.reset()
        XCTAssertEqual(lock.mode, .undecided)
        XCTAssertEqual(lock.pan(translation: 20), .scroll)
    }
}
