import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import UniverseStudio

struct AnimationExportOptionsTests {
    @Test func outputSizes() {
        #expect(ImageFiles.outputSize(101, 51, scale: 1) == (101, 51))
        #expect(ImageFiles.outputSize(101, 51, scale: 0.5) == (51, 26))
        #expect(ImageFiles.outputSize(101, 51, scale: 0.5, even: true) == (50, 26))
    }

    private func frame() -> [ArtLayer] {
        var dot = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1); dot.kind = "fill"
        var a = ArtLayer(name: "a"); a.strokes = [dot]; return [a]
    }

    @Test func scaledGIFOnceOrForever() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let forever = dir.appendingPathComponent("a.gif"), once = dir.appendingPathComponent("b.gif")
        try ImageFiles.exportGIF(frames: [frame(), frame()], width: 20, height: 10, fps: 10, scale: 0.5, url: forever)
        try ImageFiles.exportGIF(frames: [frame(), frame()], width: 20, height: 10, fps: 10, loopForever: false, url: once)
        func props(_ u: URL) -> [CFString: Any] { (CGImageSourceCopyProperties(CGImageSourceCreateWithURL(u as CFURL, nil)!, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:] }
        #expect(props(forever)[kCGImagePropertyGIFLoopCount] as? Int == 0)
        #expect(props(once)[kCGImagePropertyGIFLoopCount] as? Int != 0, "value: \(String(describing: props(once)[kCGImagePropertyGIFLoopCount]))")
        let img = try #require(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(forever as CFURL, nil)!, 0, nil))
        #expect(img.width == 10 && img.height == 5)
    }

    @Test func scaledSpriteSheet() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("json")) }
        try SpriteSheet.export(frames: [frame(), frame()], width: 20, height: 10, fps: 12, holds: [], loop: true, padding: 0, scale: 0.5, url: url)
        let meta = try JSONDecoder().decode(SpriteSheet.Meta.self, from: Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json")))
        #expect(meta.size == [20, 5] && meta.frames[1].x == 10 && meta.frames[0].w == 10)
    }
}
