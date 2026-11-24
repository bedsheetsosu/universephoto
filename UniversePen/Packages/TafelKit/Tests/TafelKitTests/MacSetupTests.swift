import XCTest
@testable import TafelKit

final class MacSetupTests: XCTestCase {
    func testSetupCarriesOnlyThePencilPart() {
        var a = InputSettings()
        a.tipThreshold = 0.3; a.sendHover = false; a.squeeze = .undo; a.hoverDotSize = 22
        let setup = MacPenSetup(a)
        var b = InputSettings()
        setup.apply(to: &b)
        XCTAssertEqual(b.tipThreshold, 0.3)
        XCTAssertFalse(b.sendHover)
        XCTAssertEqual(b.squeeze, .undo)
        XCTAssertNotEqual(b.hoverDotSize, 22)          // look settings stay shared
        XCTAssertEqual(try JSONDecoder().decode(MacPenSetup.self, from: JSONEncoder().encode(setup)), setup)
    }

    func testCalibrationMapsLightAndFirm() throws {
        let light = Array(repeating: 0.12, count: 20), firm = Array(repeating: 0.7, count: 20)
        let c = try XCTUnwrap(PressureCalibration.curve(light: light, firm: firm))
        XCTAssertEqual(c.map(0.12), 0.25, accuracy: 0.01)
        XCTAssertEqual(c.map(0.7), 0.97, accuracy: 0.01)
        XCTAssertEqual(c.map(1), 1, accuracy: 1e-9)
        XCTAssertLessThan(c.map(0.05), c.map(0.12))
        XCTAssertNil(PressureCalibration.curve(light: [0.1], firm: firm))
        // Firm almost as light as light: still a usable, rising curve.
        let close = try XCTUnwrap(PressureCalibration.curve(light: light, firm: Array(repeating: 0.13, count: 20)))
        XCTAssertGreaterThan(close.map(0.3), close.map(0.12))
    }

    func testClickThreshold() {
        XCTAssertEqual(PressureCalibration.clickThreshold(peaks: [0.5, 0.6, 0.55]), 0.33)
        XCTAssertEqual(PressureCalibration.clickThreshold(peaks: [0.02]), 0.05)
        XCTAssertNil(PressureCalibration.clickThreshold(peaks: []))
    }
}
