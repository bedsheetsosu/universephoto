import XCTest
@testable import UniverseStudio

final class UniversePenExtrasTests: XCTestCase {
    func testStatusCarriesTheDeviceDetails() throws {
        var d = PenLineDecoder()
        let line = #"{"event":"status","data":{"connected":true,"device":"iPad Air","link":"USB-Kabel (en8)","usb":true,"fps":59,"ipadBattery":0.8,"ipadCharging":false}}"# + "\n"
        let events = try d.append(Data(line.utf8))
        XCTAssertEqual(events, [.deviceStatus(PenDeviceInfo(connected: true, device: "iPad Air", link: "USB-Kabel (en8)", usb: true, fps: 59, battery: 0.8, charging: false))])
    }

    func testRepliesToOurRequestsNeverDropTheConnection() throws {
        var d = PenLineDecoder()
        XCTAssertEqual(try d.append(Data((#"{"id":2,"error":"No iPad connected"}"# + "\n").utf8)), [.reply(2, "No iPad connected")])
        XCTAssertEqual(try d.append(Data((#"{"id":3,"result":{"sent":true}}"# + "\n").utf8)), [.reply(3, nil)])
        XCTAssertThrowsError(try d.append(Data((#"{"id":1,"error":"bad"}"# + "\n").utf8)), "Our own subscribe failing still counts")
    }

    @MainActor func testPressureCurveShapesStrokePressure() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let saved = s.pressureCurve
        defer { s.pressureCurve = saved }
        s.pressureCurve = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.9), CurvePoint(x: 1, y: 1)]
        XCTAssertEqual(s.mapPressure(0.5), 0.9, accuracy: 1e-9)
        s.pressureEnabled = false
        XCTAssertEqual(s.mapPressure(0.2), 1)
    }
}
