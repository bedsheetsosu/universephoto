import CoreGraphics
import Foundation

/// Animate → Export → Sprite sheet: every frame once in a grid PNG, plus a JSON file next to it
/// (frame rectangles and durations in ms, holds included) for game engines and web players.
enum SpriteSheet {
    struct Layout: Equatable { var columns: Int; var rows: Int; var width: Int; var height: Int }

    /// Near-square grid, wider than tall; nil when it would exceed 16384 px.
    static func layout(frames n: Int, width w: Int, height h: Int, padding p: Int = 0) -> Layout? {
        guard n > 0, w > 0, h > 0 else { return nil }
        let columns = Int(Double(n).squareRoot().rounded(.up)), rows = (n + columns - 1) / columns
        let sw = columns * w + (columns - 1) * p, sh = rows * h + (rows - 1) * p
        guard sw <= 16384, sh <= 16384 else { return nil }
        return Layout(columns: columns, rows: rows, width: sw, height: sh)
    }

    static func frameRect(_ i: Int, in l: Layout, width w: Int, height h: Int, padding p: Int = 0) -> CGRect {
        CGRect(x: (i % l.columns) * (w + p), y: (i / l.columns) * (h + p), width: w, height: h)
    }

    struct Meta: Codable, Equatable {
        struct Frame: Codable, Equatable { var x: Int; var y: Int; var w: Int; var h: Int; var duration: Int }
        var image: String; var size: [Int]; var fps: Double; var loop: Bool; var frames: [Frame]
    }

    static func meta(image: String, layout l: Layout, frames n: Int, width w: Int, height h: Int, padding p: Int, fps: Double, holds: [Int], loop: Bool) -> Meta {
        Meta(image: image, size: [l.width, l.height], fps: fps, loop: loop, frames: (0..<n).map { i in
            let r = frameRect(i, in: l, width: w, height: h, padding: p)
            let hold = holds.indices.contains(i) ? max(1, holds[i]) : 1
            return .init(x: Int(r.minX), y: Int(r.minY), w: w, h: h, duration: Int((Double(hold) * 1000 / max(1, fps)).rounded()))
        })
    }

    static func render(frames: [[ArtLayer]], width w: Int, height h: Int, padding p: Int = 0) throws -> (CGImage, Layout) {
        guard let l = layout(frames: frames.count, width: w, height: h, padding: p) else { throw ImageFiles.FileError.dimensions }
        guard let ctx = Renderer.context(width: l.width, height: l.height) else { throw ImageFiles.FileError.encoder("Sprite sheet") }
        for (i, frame) in frames.enumerated() {
            guard let img = Renderer.render(layers: frame, width: w, height: h) else { throw ImageFiles.FileError.encoder("Frame \(i + 1)") }
            Renderer.drawImage(img, in: ctx, rect: frameRect(i, in: l, width: w, height: h, padding: p))
        }
        guard let sheet = ctx.makeImage() else { throw ImageFiles.FileError.encoder("Sprite sheet") }
        return (sheet, l)
    }

    /// Writes `url` (PNG) and the same name with .json.
    static func export(frames: [[ArtLayer]], width w: Int, height h: Int, fps: Double, holds: [Int], loop: Bool, padding p: Int = 2, url: URL) throws {
        guard !frames.isEmpty else { throw ImageFiles.FileError.noFrames }
        let (sheet, l) = try render(frames: frames, width: w, height: h, padding: p)
        let json = url.deletingPathExtension().appendingPathExtension("json")
        let m = meta(image: url.lastPathComponent, layout: l, frames: frames.count, width: w, height: h, padding: p, fps: fps, holds: holds, loop: loop)
        try ImageFiles.encodedData(image: sheet, type: .png, quality: 1).write(to: url, options: .atomic)
        try JSONEncoder.pretty.encode(m).write(to: json, options: .atomic)
    }
}
