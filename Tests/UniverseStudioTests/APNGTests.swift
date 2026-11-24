import Testing
import Foundation
import ImageIO
@testable import UniverseStudio

struct APNGTests {
    @Test func framesHoldsAndAlpha() throws {
        var half = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 0.5), width: 1); half.kind = "fill"
        var a = ArtLayer(name: "a"); a.strokes = [half]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageFiles.exportAPNG(frames: [[a], [ArtLayer(name: "b")]], holds: [3], width: 6, height: 6, fps: 10, url: url)
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(src) == 2)
        let delays = ImageFiles.delay(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        #expect(abs((delays ?? 0) - 0.3) < 0.01)
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let b = try #require(PixelOps.bitmap(img))
        #expect(b.bytes[3] > 100 && b.bytes[3] < 160, "semi-transparent survives (GIF can't)")
        let back = try ImageFiles.decodeFrames(url: url)
        #expect(back.count == 2)
    }
}
