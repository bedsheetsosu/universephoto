import XCTest
import CoreGraphics
@testable import TafelKit

final class WireTests: XCTestCase {
    func testPenRoundTrip() throws {
        let s = PenSample(phase: .move, x: 0.25, y: 0.75, pressure: 0.6, tiltX: -0.3, tiltY: 0.4, rotation: 123.5, timestamp: 1234.5678)
        XCTAssertEqual(try PenSample(decoding: s.encoded()), s)
    }

    func testPenRejectsTruncated() {
        let d = PenSample(phase: .down, x: 0, y: 0).encoded().dropLast()
        XCTAssertThrowsError(try PenSample(decoding: Data(d)))
    }

    func testScrollShortcutPingRoundTrip() throws {
        let sc = ScrollEvent(x: 0.5, y: 0.5, dx: -0.01, dy: 0.02, modifiers: [.command, .option])
        XCTAssertEqual(try ScrollEvent(decoding: sc.encoded()), sc)
        let k = Shortcut("Z", [.command, .shift])
        XCTAssertEqual(k.key, "z")
        XCTAssertEqual(try Shortcut(decoding: k.encoded()), k)
        XCTAssertEqual(k.display, "⇧⌘Z")
        XCTAssertEqual(try Pong(decoding: Pong(clientTime: 1, hostTime: 2).encoded()), Pong(clientTime: 1, hostTime: 2))
    }

    func testVideoRoundTrip() throws {
        let f = VideoFormat(codec: .hevc, width: 2360, height: 1640, parameterSets: [Data([1, 2]), Data([3]), Data([4, 5, 6])])
        XCTAssertEqual(try VideoFormat(decoding: f.encoded()), f)
        let c = VideoFormat(codec: .hevc, width: 10, height: 10, parameterSets: [Data([1])], displayP3: true, sRGBTransfer: true)
        XCTAssertEqual(try VideoFormat(decoding: c.encoded()), c)
        // A pre-0.8 host sends no transfer flag: BT.709 as before.
        var old = c.encoded(); old.removeLast()
        XCTAssertFalse(try VideoFormat(decoding: old).sRGBTransfer)
        XCTAssertTrue(try VideoFormat(decoding: old).displayP3)
        let v = VideoFrame(isKeyframe: true, captureTime: 99.5, data: Data(repeating: 7, count: 1000))
        XCTAssertEqual(try VideoFrame(decoding: v.encoded()), v)
    }

    func testFrameSplitHandlesPartialStream() throws {
        var stream = FrameCodec.encode(.ping, Ping(clientTime: 1).encoded())
        stream += FrameCodec.encode(.requestKeyframe, Data())
        let third = FrameCodec.encode(.pen, PenSample(phase: .up, x: 1, y: 1).encoded())
        stream += third.prefix(10)
        let (frames, rest) = try FrameCodec.split(stream)
        XCTAssertEqual(frames.map(\.type), [.ping, .requestKeyframe])
        XCTAssertEqual(rest.count, 10)
    }

    func testOversizedHeaderRejected() {
        var w = ByteWriter()
        w.u8(MessageType.videoFrame.rawValue)
        w.u32(UInt32(FrameCodec.maxPayload + 1))
        XCTAssertThrowsError(try FrameCodec.parseHeader(w.data))
    }

    func testJSONMessages() throws {
        let c = ClientConfig(viewPixelWidth: 2360, viewPixelHeight: 1640, quality: StreamQuality(codec: .hevc))
        XCTAssertEqual(try JSONWire.decode(ClientConfig.self, JSONWire.encode(c)), c)
        var s = InputSettings()
        s.doubleTap = .shortcut(Shortcut("x", .option))
        XCTAssertEqual(try JSONWire.decode(InputSettings.self, JSONWire.encode(s)), s)
    }
}

final class PairingTests: XCTestCase {
    func testCodeFormatAndNormalize() {
        let c = PairingCode.generate()
        XCTAssertEqual(c.count, 12)
        XCTAssertTrue(c.allSatisfy { PairingCode.alphabet.contains($0) })
        let f = PairingCode.formatted(c)
        XCTAssertEqual(f.count, 14)
        XCTAssertEqual(PairingCode.normalize(f.lowercased()), c)
        XCTAssertEqual(PairingCode.normalize("oil0-1111-2222"), "0110" + "11112222")
        XCTAssertNil(PairingCode.normalize("ABC"))
        XCTAssertNil(PairingCode.normalize("UUUU-UUUU-UUUU"))
    }

    func testCodesAreRandom() {
        XCTAssertEqual(Set((0..<200).map { _ in PairingCode.generate() }).count, 200)
    }

    func testPSKDeterministicAndDistinct() {
        XCTAssertEqual(PairingCode.pairingPSK(code: "ABCDEFGHJKMN"), PairingCode.pairingPSK(code: "ABCDEFGHJKMN"))
        XCTAssertNotEqual(PairingCode.pairingPSK(code: "ABCDEFGHJKMN"), PairingCode.pairingPSK(code: "ABCDEFGHJKMP"))
        XCTAssertEqual(PairingCode.pairingPSK(code: "X").count, 32)
        XCTAssertEqual(HostKey.generate().count, 32)
        XCTAssertNotEqual(HostKey.generate(), HostKey.generate())
    }
}

final class GeometryTests: XCTestCase {
    // iPad Air 11" M4: 2360 x 1640 px. MacBook Air 13": 1470 x 956 pt default.
    func testRegionMatchesIPadAspectWithoutBars() {
        let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let r = Geometry.region(aspect: 2360.0 / 1640.0, in: display)
        XCTAssertEqual(r.height, 956, accuracy: 0.001)
        XCTAssertEqual(r.width / r.height, 2360.0 / 1640.0, accuracy: 0.0001)
        XCTAssertEqual(r.midX, display.midX, accuracy: 0.001)
        let size = Geometry.streamSize(sourceAspect: Double(r.width / r.height), targetWidth: 2360, targetHeight: 1640, scale: 1)
        XCTAssertEqual(size.width, 2360)
        XCTAssertEqual(size.height, 1640)
    }

    func testRegionZoomAndAnchor() {
        let b = CGRect(x: 100, y: 50, width: 1000, height: 1000)
        let r = Geometry.region(aspect: 2, in: b, zoom: 0.5, anchor: CGPoint(x: 0, y: 1))
        XCTAssertEqual(r, CGRect(x: 100, y: 50 + 1000 - 250, width: 500, height: 250))
    }

    func testFullDisplayLetterboxMapping() {
        let view = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let video = Geometry.aspectFit(content: CGSize(width: 1470, height: 956), in: view)
        XCTAssertEqual(video.width, 1180, accuracy: 0.001)
        XCTAssertLessThan(video.height, 820)
        let n = Geometry.normalized(CGPoint(x: video.midX, y: video.minY), in: video)
        XCTAssertEqual(n.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(n.y, 0, accuracy: 1e-9)
        // Touches in the black bar clamp to the edge instead of escaping the capture.
        XCTAssertEqual(Geometry.normalized(CGPoint(x: -10, y: 900), in: video), CGPoint(x: 0, y: 1))
    }

    func testDenormalizeOnSecondaryDisplay() {
        let region = CGRect(x: -1920, y: -200, width: 1000, height: 500)
        XCTAssertEqual(Geometry.denormalized(CGPoint(x: 0.5, y: 0.5), in: region), CGPoint(x: -1420, y: 50))
    }

    func testStreamSizeEvenAndScaled() {
        let s = Geometry.streamSize(sourceAspect: 1470.0 / 956.0, targetWidth: 2360, targetHeight: 1640, scale: 0.5)
        XCTAssertEqual(s.width % 2, 0)
        XCTAssertEqual(s.height % 2, 0)
        XCTAssertEqual(s.width, 1180)
    }

    func testTilt() {
        let t = TiltConverter()
        let up = t.tilt(altitude: .pi / 2, azimuth: 1)
        XCTAssertEqual(up.x, 0, accuracy: 1e-9)
        XCTAssertEqual(up.y, 0, accuracy: 1e-9)
        let flatRight = t.tilt(altitude: 0, azimuth: 0)
        XCTAssertEqual(flatRight.x, 1, accuracy: 1e-9)
        let inv = TiltConverter(invertX: true, invertY: true).tilt(altitude: .pi / 4, azimuth: .pi / 2)
        XCTAssertEqual(inv.x, 0, accuracy: 1e-9)
        XCTAssertEqual(inv.y, -cos(.pi / 4), accuracy: 1e-9)
    }

    func testPressureCurve() {
        let lin = PressureCurve(gamma: 1, minimum: 0.01)
        XCTAssertEqual(lin.apply(force: 2, maximumForce: 4), 0.5, accuracy: 1e-9)
        XCTAssertEqual(lin.apply(force: 0, maximumForce: 4), 0.01, accuracy: 1e-9)
        XCTAssertEqual(lin.apply(force: 10, maximumForce: 4), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(PressureCurve(gamma: 0.5).apply(force: 1, maximumForce: 4), 0.25)
    }

    func testAccumulators() {
        var d = DeltaAccumulator()
        XCTAssertEqual(d.take(0.6), 0)
        XCTAssertEqual(d.take(0.6), 1)
        XCTAssertEqual(d.take(-2.4), -2)
        var s = StepAccumulator(stepSize: 15)
        XCTAssertEqual(s.add(10), 0)
        XCTAssertEqual(s.add(10), 1)
        XCTAssertEqual(s.add(-40), -2)
    }

    func testAudioChunkRoundTrip() throws {
        var w = ByteWriter()
        for v: Int16 in [0, 1000, -1000, 32767, -32768, 5] { w.u16(UInt16(bitPattern: v)) }
        let c = AudioChunk(sampleRate: 48_000, channels: 2, captureTime: 1234.5, samples: w.data)
        let d = try AudioChunk(decoding: c.encoded())
        XCTAssertEqual(d, c)
        XCTAssertEqual(d.frameCount, 3)
    }

    func testAudioChunkRejectsOddLength() {
        var w = ByteWriter()
        w.u32(48_000); w.u8(2); w.f64(0); w.u8(1); w.u8(2); w.u8(3)
        XCTAssertThrowsError(try AudioChunk(decoding: w.data))
    }

    func testStreamQualityDecodesOldSettings() throws {
        let old = #"{"codec":"hevc","bitrateMbps":20,"fps":30,"resolutionScale":0.5}"#
        let q = try JSONDecoder().decode(StreamQuality.self, from: Data(old.utf8))
        XCTAssertEqual(q.codec, .hevc)
        XCTAssertEqual(q.fps, 30)
        XCTAssertTrue(q.audio)
    }

    func testKeyEventRoundTrip() throws {
        let k = KeyEvent(hidUsage: 0xE3, down: true)
        XCTAssertEqual(try KeyEvent(decoding: k.encoded()), k)
        XCTAssertEqual(try TextInput(decoding: TextInput("Grüße ✏️").encoded()).text, "Grüße ✏️")
    }

    func testHIDKeyMap() {
        XCTAssertEqual(HIDKeyMap.macKeyCode(0x04), 0x00)            // A
        XCTAssertEqual(HIDKeyMap.macKeyCode(0x1D), 0x06)            // Z (QWERTY position; Mac layout decides the letter)
        XCTAssertEqual(HIDKeyMap.macKeyCode(0x28), 0x24)            // Return
        XCTAssertEqual(HIDKeyMap.macKeyCode(0x64), 0x0A)            // ISO "<"
        XCTAssertEqual(HIDKeyMap.macKeyCode(0xE3), 0x37)            // left Cmd
        XCTAssertEqual(HIDKeyMap.modifier(macKeyCode: 0x37), .command)
        XCTAssertNil(HIDKeyMap.macKeyCode(0x00))
        XCTAssertEqual(HIDKeyMap.swapISO(0x35), 0x64)
        XCTAssertEqual(HIDKeyMap.swapISO(0x04), 0x04)
        XCTAssertTrue(HIDKeyMap.needsFunctionFlag(macKeyCode: 0x7E))
    }

    func testInputSettingsDecodesOldSettings() throws {
        var old = InputSettings()
        old.sendHover = false
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json["swapISOKeys"] = nil
        let decoded = try JSONDecoder().decode(InputSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.sendHover)
        XCTAssertFalse(decoded.swapISOKeys)
    }

    func testMouseEventRoundTrip() throws {
        let m = MouseEvent(phase: .down, button: .right, x: 0.25, y: 0.75)
        XCTAssertEqual(try MouseEvent(decoding: m.encoded()), m)
        var bad = m.encoded(); bad[0] = 9
        XCTAssertThrowsError(try MouseEvent(decoding: bad))
    }
}

final class OneFingerGestureTests: XCTestCase {
    func testTapIsClickAtStartPoint() {
        var g = OneFingerGesture()
        XCTAssertEqual(g.begin(CGPoint(x: 10, y: 10), at: 0), [])
        XCTAssertEqual(g.move(CGPoint(x: 13, y: 12), at: 0.05), [])          // jitter below threshold
        XCTAssertEqual(g.end(CGPoint(x: 13, y: 12)), [.click(CGPoint(x: 10, y: 10))])
        XCTAssertFalse(g.isActive)
    }

    func testDragPressesAtStartThenDrags() {
        var g = OneFingerGesture()
        _ = g.begin(CGPoint(x: 0, y: 0), at: 0)
        XCTAssertEqual(g.move(CGPoint(x: 20, y: 0), at: 0.1), [.press(.zero), .drag(CGPoint(x: 20, y: 0))])
        XCTAssertEqual(g.move(CGPoint(x: 30, y: 0), at: 0.2), [.drag(CGPoint(x: 30, y: 0))])
        XCTAssertEqual(g.end(CGPoint(x: 30, y: 0)), [.release(CGPoint(x: 30, y: 0))])
    }

    func testHoldIsRightClickOnce() {
        var g = OneFingerGesture()
        _ = g.begin(CGPoint(x: 5, y: 5), at: 1)
        XCTAssertEqual(g.tick(at: 1.3), [])
        XCTAssertEqual(g.tick(at: 1.6), [.rightClick(CGPoint(x: 5, y: 5))])
        XCTAssertEqual(g.tick(at: 2.0), [])
        XCTAssertEqual(g.move(CGPoint(x: 50, y: 5), at: 2.1), [])            // no drag after right click
        XCTAssertEqual(g.end(CGPoint(x: 50, y: 5)), [])
    }

    func testLongPressCanBeDisabled() {
        var g = OneFingerGesture()
        g.longPressEnabled = false
        _ = g.begin(.zero, at: 0)
        XCTAssertEqual(g.tick(at: 5), [])
        XCTAssertEqual(g.end(.zero), [.click(.zero)])
    }

    func testSecondFingerEndsDragAndSuppressesClick() {
        var g = OneFingerGesture()
        _ = g.begin(.zero, at: 0)
        _ = g.move(CGPoint(x: 40, y: 0), at: 0.1)
        XCTAssertEqual(g.cancel(), [.release(CGPoint(x: 40, y: 0))])
        XCTAssertEqual(g.end(CGPoint(x: 60, y: 0)), [])

        var tap = OneFingerGesture()
        _ = tap.begin(.zero, at: 0)
        XCTAssertEqual(tap.cancel(), [])                                       // two-finger tap: no click
        XCTAssertEqual(tap.end(.zero), [])
    }
}

final class PressureCurveTests: XCTestCase {
    func testGammaFallback() {
        let c = PressureCurve(gamma: 2)
        XCTAssertEqual(c.map(0.5), 0.25, accuracy: 1e-9)
    }

    func testPointsHitControlPointsAndStayMonotone() {
        let c = PressureCurve(points: [CurvePoint(0, 0), CurvePoint(0.3, 0.6), CurvePoint(0.6, 0.65), CurvePoint(1, 1)])
        XCTAssertEqual(c.map(0.3), 0.6, accuracy: 1e-9)
        XCTAssertEqual(c.map(1), 1, accuracy: 1e-9)
        var last = -1.0
        for i in 0...100 {
            let y = c.map(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(y, last - 1e-12)
            XCTAssertTrue((0...1).contains(y))
            last = y
        }
    }

    func testEditablePointsReproduceGamma() {
        let c = PressureCurve(gamma: 0.6)
        let e = PressureCurve(points: c.editablePoints())
        XCTAssertEqual(e.map(0.5), c.map(0.5), accuracy: 1e-9)
    }

    func testOldSettingsDecode() throws {
        let c = try JSONDecoder().decode(PressureCurve.self, from: Data(#"{"gamma":1.5,"minimum":0.02}"#.utf8))
        XCTAssertEqual(c.gamma, 1.5); XCTAssertTrue(c.points.isEmpty)
    }

    func testSmoother() {
        var s = SampleSmoother(amount: 0)
        XCTAssertEqual(s.add(1), 1); XCTAssertEqual(s.add(0), 0)
        var t = SampleSmoother(amount: 1)
        _ = t.add(0)
        XCTAssertEqual(t.add(1), 0.15, accuracy: 1e-9)
    }
}

final class PatchTests: XCTestCase {
    func testDeepMergeKeepsSiblings() {
        var st = InputSettings()
        st.appShortcutBars["a"] = [ShortcutButton(title: "A", shortcut: Shortcut("a"))]
        let btn = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(ShortcutButton(title: "B", shortcut: Shortcut("b", .command))))
        let out = applyPatch(st, ["appShortcutBars": ["b": [btn]], "fingerPressure": 0.8])!
        XCTAssertEqual(out.appShortcutBars["a"]?.first?.title, "A")
        XCTAssertEqual(out.appShortcutBars["b"]?.first?.shortcut, Shortcut("b", .command))
        XCTAssertEqual(out.fingerPressure, 0.8)
    }

    func testPressureCurvePatch() {
        let out = applyPatch(InputSettings(), ["pressure": ["points": [["x": 0, "y": 0], ["x": 0.5, "y": 0.8], ["x": 1, "y": 1]]]])!
        XCTAssertEqual(out.pressure.points.count, 3)
        XCTAssertEqual(out.pressure.minimum, 0.01)   // sibling kept
    }

    func testClipboardItemRoundTrip() throws {
        let t = ClipboardItem.text("Grüße ✏️")
        XCTAssertEqual(try ClipboardItem(decoding: t.encoded()).text, "Grüße ✏️")
        let png = ClipboardItem(kind: .png, data: Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(try ClipboardItem(decoding: png.encoded()), png)
        XCTAssertEqual(try ClipboardItem(decoding: ClipboardItem(kind: .empty).encoded()).kind, .empty)
        XCTAssertThrowsError(try ClipboardItem(decoding: Data([9, 1, 2])))
        XCTAssertThrowsError(try ClipboardItem(decoding: Data()))
    }

    func testTenBitOnlyWithHEVC() throws {
        XCTAssertTrue(StreamQuality(codec: .hevc).usesTenBit)
        XCTAssertFalse(StreamQuality(codec: .h264).usesTenBit)
        XCTAssertFalse(StreamQuality(codec: .hevc, tenBit: false).usesTenBit)
        // Settings saved before 0.8 have no tenBit key.
        let old = try JSONDecoder().decode(StreamQuality.self, from: Data(#"{"codec":"hevc"}"#.utf8))
        XCTAssertTrue(old.usesTenBit)
    }

    func testHeatGuardOnlyLowers() {
        let q = StreamQuality(codec: .hevc, bitrateMbps: 60, fps: 60, resolutionScale: 1, fullSource: true)
        XCTAssertEqual(q.cooled(level: 0), q)
        let hot = q.cooled(level: 1)
        XCTAssertEqual(hot.fps, 30); XCTAssertFalse(hot.fullSource); XCTAssertEqual(hot.bitrateMbps, 25); XCTAssertEqual(hot.resolutionScale, 1)
        let critical = q.cooled(level: 2)
        XCTAssertEqual(critical.bitrateMbps, 15); XCTAssertEqual(critical.resolutionScale, 0.75)
        // Already lower settings stay as they are.
        let low = StreamQuality(bitrateMbps: 10, fps: 30, resolutionScale: 0.5, fullSource: false)
        XCTAssertEqual(low.cooled(level: 2), low)
    }

    func testPausedRestartsTheStream() {
        let a = ClientConfig(viewPixelWidth: 10, viewPixelHeight: 10, quality: StreamQuality())
        var b = a
        b.paused = true
        XCTAssertFalse(a.sameStream(as: b))
        b.paused = false
        XCTAssertTrue(a.sameStream(as: b))
    }
}
