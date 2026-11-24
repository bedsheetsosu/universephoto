import XCTest
@testable import UniverseStudio

final class PenProtocolTests: XCTestCase {
    func testFragmentedAndCoalescedLines() throws {
        var decoder = PenLineDecoder()
        XCTAssertEqual(try decoder.append(Data("{\"event\":\"hel".utf8)), [])
        let events = try decoder.append(Data("lo\",\"data\":{\"api\":1,\"app\":\"UniversePen\"}}\n{\"id\":1,\"result\":{\"topics\":[\"input\",\"status\"]}}\n".utf8))
        XCTAssertEqual(events, [.hello(1), .subscribed])
    }
    func testPressureTiltHoverAndNegativeScreenCoordinates() throws {
        let line = Data(#"{"event":"pen","data":{"phase":"hover","x":0.3,"y":0.9,"screenX":-240,"screenY":-32,"pressure":1.2,"tiltX":0.4,"tiltY":-0.2,"rotation":183.5,"timestamp":1234}}"#.utf8)
        guard case .pen(let sample) = try PenLineDecoder.decode(line) else { return XCTFail("Missing pen") }
        XCTAssertEqual(sample.phase, "hover")
        XCTAssertEqual(sample.pressure, 1)
        XCTAssertEqual(sample.screenX, -240)
        XCTAssertEqual(sample.rotation, 183.5)
        XCTAssertEqual(sample.tiltY, -0.2)
        XCTAssertEqual(sample.timestamp, 1234)
    }
    func testDisconnectResetsIncompleteMessage() throws {
        var decoder = PenLineDecoder()
        _ = try decoder.append(Data("{\"event\":\"pen\",\"data\":".utf8))
        decoder.reset()
        XCTAssertEqual(try decoder.append(Data("{\"event\":\"hello\",\"data\":{\"api\":1}}\n".utf8)), [.hello(1)])
    }
    func testRejectsIncompatibleAndMalformedInput() throws {
        XCTAssertThrowsError(try PenLineDecoder.decode(Data(#"{"event":"hello","data":{"api":2}}"#.utf8)))
        XCTAssertThrowsError(try PenLineDecoder.decode(Data(#"{"event":"pen","data":{"phase":"wrong","x":0,"y":0,"pressure":0}}"#.utf8)))
        XCTAssertThrowsError(try PenLineDecoder.decode(Data(#"{"id":1,"error":"not enabled"}"#.utf8)))
        var decoder = PenLineDecoder()
        XCTAssertThrowsError(try decoder.append(Data(repeating: 65, count: PenLineDecoder.limit + 1)))
        XCTAssertEqual(try decoder.append(Data("{\"event\":\"status\",\"data\":{\"connected\":false}}\n".utf8)), [.deviceStatus(PenDeviceInfo(connected: false))])
    }
}
