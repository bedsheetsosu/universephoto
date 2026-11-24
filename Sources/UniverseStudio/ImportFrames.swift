import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Animate → Import frames…: several images (sorted by name, "frame-2" before "frame-10") or one
/// animated GIF/PNG become new frames after the current one. Each picture lands in the selected
/// layer, centred and shrunk to fit if it is bigger than the canvas; GIF timing becomes holds.
extension ImageFiles {
    static let maxImportedFrames = 600

    /// Every picture in the file with its delay in seconds (nil when the file has none).
    static func decodeFrames(url: URL) throws -> [(image: CGImage, delay: Double?)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw FileError.unsupported(url.pathExtension) }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw FileError.invalidImage }
        guard count <= maxImportedFrames else { throw FileError.unsupported("More than \(maxImportedFrames) frames") }
        return try (0..<count).map { i in
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { throw FileError.invalidImage }
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            return (image, delay(props))
        }
    }

    static func delay(_ props: [CFString: Any]?) -> Double? {
        for key in [kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary] {
            guard let d = props?[key] as? [CFString: Any] else { continue }
            let v = (d[kCGImagePropertyGIFUnclampedDelayTime] ?? d[kCGImagePropertyAPNGUnclampedDelayTime] ?? d[kCGImagePropertyGIFDelayTime] ?? d[kCGImagePropertyAPNGDelayTime]) as? Double
            if let v, v > 0 { return v }
        }
        return nil
    }

    /// `image` centred on a `width` × `height` canvas, scaled down (never up) to fit.
    static func fitted(_ image: CGImage, width w: Int, height h: Int) -> CGImage? {
        guard let ctx = Renderer.context(width: w, height: h) else { return nil }
        let k = min(1, min(Double(w) / Double(image.width), Double(h) / Double(image.height)))
        let iw = Double(image.width) * k, ih = Double(image.height) * k
        ctx.interpolationQuality = k < 1 ? .high : .none
        Renderer.drawImage(image, in: ctx, rect: CGRect(x: ((Double(w) - iw) / 2).rounded(), y: ((Double(h) - ih) / 2).rounded(), width: iw, height: ih))
        return ctx.makeImage()
    }

    /// Holds from delays at `fps` (at least 1 tick each).
    static func holds(_ delays: [Double?], fps: Double) -> [Int] {
        delays.map { d in d.map { max(1, Int(($0 * max(1, fps)).rounded())) } ?? 1 }
    }
}

extension Studio {
    /// Inserts the pictures as frames after the current one. Returns how many were added.
    @discardableResult func importFrames(_ items: [(image: CGImage, delay: Double?)]) -> Int {
        guard !items.isEmpty, layers.indices.contains(selectedLayer) else { return 0 }
        let pngs = items.compactMap { ImageFiles.fitted($0.image, width: width, height: height).flatMap { try? Renderer.png($0) } }
        guard pngs.count == items.count else { return 0 }
        stopPlayback(); checkpoint("Import frames")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let template = layers.map { var l = $0; l.strokes = []; l.imageData = nil; l.mask = nil; return l }
        var h = (0..<frames.count).map { hold($0) }
        let newHolds = ImageFiles.holds(items.map(\.delay), fps: fps)
        for (k, png) in pngs.enumerated() {
            var f = template; f[selectedLayer].imageData = png
            frames.insert(f, at: frameIndex + 1 + k); h.insert(newHolds[k], at: frameIndex + 1 + k)
        }
        frameHolds = h; normalizeHolds(); referenceInserted(at: frameIndex + 1, count: pngs.count)
        frameIndex += 1; layers = frames[frameIndex]; selection = nil
        changed()
        return pngs.count
    }

    func importFramesPanel() {
        let p = NSOpenPanel(); p.title = L("Import frames"); p.prompt = L("Import")
        p.allowedContentTypes = ImageFiles.supportedImports; p.allowsMultipleSelection = true
        guard p.runModal() == .OK, !p.urls.isEmpty else { return }
        do {
            let urls = p.urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            var items: [(image: CGImage, delay: Double?)] = []
            for url in urls { items += try ImageFiles.decodeFrames(url: url); guard items.count <= ImageFiles.maxImportedFrames else { throw ImageFiles.FileError.unsupported("More than \(ImageFiles.maxImportedFrames) frames") } }
            importFrames(items)
        } catch { report(error) }
    }
}
