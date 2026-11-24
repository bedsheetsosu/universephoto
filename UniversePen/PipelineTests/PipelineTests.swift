import XCTest
import VideoToolbox
import CoreMedia
import CoreVideo
import TafelKit

/// End-to-end video path on this Mac, without screen capture permission:
/// synthetic frames -> host VideoEncoder (VideoToolbox) -> wire encoding -> client format/sample
/// construction (VideoRenderer statics) -> VTDecompressionSession decode.
final class PipelineTests: XCTestCase {
    private func makeFrame(width: Int, height: Int, value: UInt8) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attrs, &pb)
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        for plane in 0..<CVPixelBufferGetPlaneCount(buf) {
            let base = CVPixelBufferGetBaseAddressOfPlane(buf, plane)!
            let rows = CVPixelBufferGetHeightOfPlane(buf, plane)
            let bpr = CVPixelBufferGetBytesPerRowOfPlane(buf, plane)
            for y in 0..<rows {
                memset(base + y * bpr, Int32(plane == 0 ? (Int(value) + y) & 0xFF : 128), bpr)
            }
        }
        CVPixelBufferUnlockBaseAddress(buf, [])
        return buf
    }

    private func roundTrip(codec: VideoCodec, width: Int, height: Int) throws {
        let quality = StreamQuality(codec: codec, bitrateMbps: 20, fps: 60, resolutionScale: 1)
        let encoder = try VideoEncoder(codec: codec, width: width, height: height, quality: quality)
        print("encoder \(codec): hardware=\(encoder.isHardware) lowLatencyRC=\(encoder.usesLowLatencyRC)")

        let lock = NSLock()
        var wire: [Data] = []   // what the host would put on the socket
        let produced = expectation(description: "encoded")
        produced.expectedFulfillmentCount = 10
        encoder.onOutput = { format, frame in
            lock.withLock {
                if let format { wire.append(FrameCodec.encode(.videoFormat, format.encoded())) }
                wire.append(FrameCodec.encode(.videoFrame, frame.encoded()))
            }
            produced.fulfill()
        }
        for i in 0..<10 {
            encoder.encode(makeFrame(width: width, height: height, value: UInt8(i * 20)),
                           pts: CMTime(value: CMTimeValue(i), timescale: 60), captureTime: Double(i))
        }
        wait(for: [produced], timeout: 10)
        encoder.invalidate()

        // Client side: parse stream, build format description + samples, decode.
        let (frames, rest) = try FrameCodec.split(wire.reduce(Data(), +))
        XCTAssertTrue(rest.isEmpty)
        XCTAssertEqual(frames.first?.type, .videoFormat, "first message must carry parameter sets")
        let format = try VideoFormat(decoding: frames[0].payload)
        XCTAssertEqual(format.width, width)
        XCTAssertEqual(format.parameterSets.count, codec == .h264 ? 2 : 3)
        let desc = try XCTUnwrap(VideoRenderer.makeDescription(format))
        let dims = CMVideoFormatDescriptionGetDimensions(desc)
        XCTAssertEqual(Int(dims.width), width)
        XCTAssertEqual(Int(dims.height), height)

        var decoder: VTDecompressionSession?
        XCTAssertEqual(VTDecompressionSessionCreate(allocator: nil, formatDescription: desc, decoderSpecification: nil,
                                                    imageBufferAttributes: nil, outputCallback: nil, decompressionSessionOut: &decoder), noErr)
        var decoded = 0
        let videoFrames = try frames.filter { $0.type == .videoFrame }.map { try VideoFrame(decoding: $0.payload) }
        XCTAssertTrue(videoFrames.first?.isKeyframe == true, "stream must start with a keyframe")
        XCTAssertEqual(videoFrames.count, 10)
        for f in videoFrames {
            let sample = try XCTUnwrap(VideoRenderer.makeSample(f.data, desc))
            let status = VTDecompressionSessionDecodeFrame(decoder!, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { status, _, image, _, _ in
                if status == noErr, let image, CVPixelBufferGetWidth(image) == width { decoded += 1 }
            }
            XCTAssertEqual(status, noErr)
        }
        VTDecompressionSessionWaitForAsynchronousFrames(decoder!)
        XCTAssertEqual(decoded, 10)
        VTDecompressionSessionInvalidate(decoder!)
    }

    // iPad Air 11" M4 native landscape resolution.
    func testH264NativeIPadResolution() throws { try roundTrip(codec: .h264, width: 2360, height: 1640) }
    func testHEVCNativeIPadResolution() throws { try roundTrip(codec: .hevc, width: 2360, height: 1640) }

    func testKeyframeOnRequest() throws {
        let enc = try VideoEncoder(codec: .h264, width: 640, height: 480, quality: StreamQuality(bitrateMbps: 5))
        var keys: [Bool] = []
        let lock = NSLock()
        let done = expectation(description: "frames")
        done.expectedFulfillmentCount = 6
        enc.onOutput = { _, f in lock.withLock { keys.append(f.isKeyframe) }; done.fulfill() }
        for i in 0..<6 {
            if i == 4 { enc.requestKeyframe() }
            enc.encode(makeFrame(width: 640, height: 480, value: UInt8(i)), pts: CMTime(value: CMTimeValue(i), timescale: 60), captureTime: 0)
            Thread.sleep(forTimeInterval: 0.05)
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(keys.first, true)
        XCTAssertEqual(keys[4], true, "requested keyframe")
        XCTAssertEqual(keys[1...3].filter { $0 }.count, 0, "no unrequested keyframes in between")
    }

    /// Only reads the keyboard layout; posts no events.
    func testKeyboardLayoutResolvesLetters() {
        XCTAssertNotNil(KeyboardLayout.keyCode(for: "z"))
        XCTAssertNotNil(KeyboardLayout.keyCode(for: "e"))
        XCTAssertEqual(KeyboardLayout.keyCode(for: "esc")?.code, 53)
        XCTAssertNotEqual(KeyboardLayout.keyCode(for: "z")?.code, KeyboardLayout.keyCode(for: "e")?.code)
    }
}
