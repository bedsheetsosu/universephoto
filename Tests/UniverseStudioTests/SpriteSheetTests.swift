import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import UniverseStudio

struct SpriteSheetTests {
    @Test func gridIsNearSquare() {
        #expect(SpriteSheet.layout(frames: 5, width: 10, height: 8) == .init(columns: 3, rows: 2, width: 30, height: 16))
        #expect(SpriteSheet.layout(frames: 4, width: 10, height: 8, padding: 2) == .init(columns: 2, rows: 2, width: 22, height: 18))
        #expect(SpriteSheet.layout(frames: 100, width: 4000, height: 10) == nil, "too wide")
        let l = SpriteSheet.layout(frames: 5, width: 10, height: 8, padding: 2)!
        #expect(SpriteSheet.frameRect(4, in: l, width: 10, height: 8, padding: 2) == CGRect(x: 12, y: 10, width: 10, height: 8))
    }

    @Test func metaCarriesHolds() {
        let l = SpriteSheet.layout(frames: 3, width: 10, height: 10)!
        let m = SpriteSheet.meta(image: "a.png", layout: l, frames: 3, width: 10, height: 10, padding: 0, fps: 10, holds: [1, 3], loop: true)
        #expect(m.frames.map(\.duration) == [100, 300, 100] && m.frames[2].x == 0 && m.frames[2].y == 10)
    }

    @Test func writesPNGAndJSON() throws {
        var dot = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1); dot.kind = "fill"
        var a = ArtLayer(name: "a"); a.strokes = [dot]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("walk.png")
        try SpriteSheet.export(frames: [[a], [ArtLayer(name: "b")]], width: 6, height: 4, fps: 12, holds: [], loop: true, padding: 2, url: url)
        let meta = try JSONDecoder().decode(SpriteSheet.Meta.self, from: Data(contentsOf: dir.appendingPathComponent("walk.json")))
        #expect(meta.image == "walk.png" && meta.size == [14, 4] && meta.frames.count == 2 && meta.frames[1].x == 8)
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let b = try #require(PixelOps.bitmap(img))
        #expect(img.width == 14 && b.bytes[3] == 255 && b.bytes[(9) * 4 + 3] == 0, "frame 1 filled, frame 2 empty")
    }
}
