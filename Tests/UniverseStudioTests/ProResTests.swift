import Testing
import Foundation
import AVFoundation
@testable import UniverseStudio

struct ProResTests {
    @Test func movWithAlphaAndSound() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var dot = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 8, y: 8, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1)
        dot.kind = "rectangle"; dot.filled = true
        var a = ArtLayer(name: "a"); a.strokes = [dot]
        let cache = try AudioCache(track: AudioTrack(name: "t", data: testWAV(), fileExtension: "wav"))
        let out = dir.appendingPathComponent("a.mov")
        try await ImageFiles.exportVideo(frames: Array(repeating: [a], count: 6), width: 16, height: 16, fps: 6, sound: (cache.url, 0, 1), proRes: true, url: out)
        let asset = AVURLAsset(url: out)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await video.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_AppleProRes4444)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        // A pixel outside the rectangle stays transparent.
        let gen = AVAssetImageGenerator(asset: asset); gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        let img = try await gen.image(at: .zero).image
        let b = try #require(PixelOps.bitmap(img))
        #expect(b.bytes[(14 * img.width + 14) * 4 + 3] < 10 && b.bytes[(2 * img.width + 2) * 4 + 3] > 240)
    }
}
