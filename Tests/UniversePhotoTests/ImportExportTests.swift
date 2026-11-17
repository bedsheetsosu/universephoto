import XCTest
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation
@testable import UniversePhoto

final class ImportExportTests: XCTestCase, @unchecked Sendable {
    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("UniversePhoto-IO-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    private func fixture() -> ArtLayer {
        var layer = ArtLayer(name: "Export alpha")
        layer.strokes = [InkStroke(points: [InkPoint(x: 12, y: 7, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 0.5), width: 8)]
        return layer
    }

    func testPNGAndTIFFRetainAlphaAndDimensions() throws {
        let dir = try temporaryDirectory()
        let image = try XCTUnwrap(Renderer.render(layers: [fixture()], width: 40, height: 32))
        for type in [UTType.png, .tiff] {
            let url = dir.appendingPathComponent("alpha.\(type.preferredFilenameExtension!)")
            try ImageFiles.export(image: image, url: url, type: type)
            let imported = try ImageFiles.importImage(url: url)
            XCTAssertEqual(imported.width, 40); XCTAssertEqual(imported.height, 32)
            let roundTrip = try XCTUnwrap(Renderer.render(layers: [imported.layer], width: imported.width, height: imported.height))
            XCTAssertEqual(Renderer.sample(roundTrip, at: CGPoint(x: 12, y: 7)).alpha, 0.5, accuracy: 0.04)
            XCTAssertEqual(Renderer.sample(roundTrip, at: .zero).alpha, 0, accuracy: 0.01)
        }
    }

    func testJPEGFlattensTransparencyOverWhite() throws {
        let dir = try temporaryDirectory(), url = dir.appendingPathComponent("flat.jpg")
        let image = try XCTUnwrap(Renderer.render(layers: [], width: 32, height: 32))
        try ImageFiles.export(image: image, url: url, type: .jpeg)
        let imported = try ImageFiles.importImage(url: url)
        let roundTrip = try XCTUnwrap(Renderer.render(layers: [imported.layer], width: 32, height: 32))
        let sample = Renderer.sample(roundTrip, at: CGPoint(x: 10, y: 10))
        XCTAssertEqual(sample.alpha, 1, accuracy: 0.01)
        XCTAssertEqual(sample.red, 1, accuracy: 0.02)
        XCTAssertEqual(sample.green, 1, accuracy: 0.02)
        XCTAssertEqual(sample.blue, 1, accuracy: 0.02)
    }

    func testGIFHasEveryFrameAndLoopMetadata() throws {
        let dir = try temporaryDirectory(), url = dir.appendingPathComponent("loop.gif")
        try ImageFiles.exportGIF(frames: [[fixture()], []], width: 40, height: 32, fps: 10, url: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        let properties = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        XCTAssertEqual(gif[kCGImagePropertyGIFLoopCount] as? Int, 0)
        let frame = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let timing = try XCTUnwrap(frame[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        XCTAssertEqual(try XCTUnwrap(timing[kCGImagePropertyGIFDelayTime] as? Double), 0.1, accuracy: 0.001)
    }

    func testSequenceRefusesCollisionWithoutOverwriting() throws {
        let dir = try temporaryDirectory()
        try ImageFiles.exportSequence(frames: [[fixture()], []], width: 40, height: 32, directory: dir)
        let first = dir.appendingPathComponent("frame-0001.png")
        let before = try Data(contentsOf: first)
        XCTAssertThrowsError(try ImageFiles.exportSequence(frames: [[]], width: 40, height: 32, directory: dir))
        XCTAssertEqual(try Data(contentsOf: first), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("frame-0002.png").path))
    }

    func testMP4HasTrackResolutionAndDuration() async throws {
        let dir = try temporaryDirectory(), url = dir.appendingPathComponent("animation.mp4")
        try await ImageFiles.exportVideo(frames: [[fixture()], []], width: 64, height: 64, fps: 8, url: url)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 64); XCTAssertEqual(size.height, 64)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 0.25, accuracy: 0.02)
        let frame = try await AVAssetImageGenerator(asset: asset).image(at: .zero).image
        let ink = Renderer.sample(frame, at: CGPoint(x: 12, y: 7))
        let lower = Renderer.sample(frame, at: CGPoint(x: 12, y: 57))
        XCTAssertLessThan(ink.green, 0.8, "Video must preserve top-left orientation")
        XCTAssertGreaterThan(lower.green, 0.9)
    }

    func testRejectsInvalidDimensionsAndEmptyAnimation() {
        XCTAssertThrowsError(try ImageFiles.validate(width: 0, height: 32))
        XCTAssertThrowsError(try ImageFiles.validate(width: 8193, height: 32))
        XCTAssertThrowsError(try ImageFiles.exportGIF(frames: [], width: 32, height: 32, fps: 12, url: URL(fileURLWithPath: "/tmp/not-written.gif")))
    }
}
