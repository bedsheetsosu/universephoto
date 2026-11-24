import SwiftUI
import ImageIO

/// Edit → Define pattern (the visible picture inside the selection) and Fill with pattern
/// (tiles it into the selection, or the whole layer, as one picture stroke). Patterns are kept
/// across documents, newest first, at most 12.
extension Studio {
    static let patternsKey = "patterns", maxPatterns = 12, maxPatternSide = 1024

    static func loadPatterns(_ d: UserDefaults = .standard) -> [Data] { (d.array(forKey: patternsKey) as? [Data]) ?? [] }
    func savePatterns() { patternStore?.set(patterns, forKey: Self.patternsKey) }

    /// Crops what is visible inside the selection's bounds. False without a usable selection.
    @discardableResult func definePattern() -> Bool {
        guard let sel = selection else { return false }
        let box = sel.bounds.standardized.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard box.width >= 1, box.height >= 1, box.width <= Double(Self.maxPatternSide), box.height <= Double(Self.maxPatternSide),
              let all = Renderer.render(layers: composite(layers), width: width, height: height),
              let tile = all.cropping(to: box), let data = PixelOps.png(tile) else { return false }
        patterns.insert(data, at: 0)
        if patterns.count > Self.maxPatterns { patterns.removeLast(patterns.count - Self.maxPatterns) }
        savePatterns()
        return true
    }

    /// `pattern` repeated over the document from its top-left corner, kept where `mask` is set.
    static func tiled(_ pattern: PixelOps.Bitmap, mask: [UInt8]?, width w: Int, height h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let py = y % pattern.height
            for x in 0..<w {
                let m = mask.map { Int($0[y * w + x]) } ?? 255
                guard m > 0 else { continue }
                let src = pattern.index(x % pattern.width, py), dst = (y * w + x) * 4
                for k in 0..<4 { out[dst + k] = UInt8(Int(pattern.bytes[src + k]) * m / 255) }
            }
        }
        return out
    }

    /// Fills the selection (or everything) on the active layer with pattern `index`.
    @discardableResult func fillWithPattern(_ index: Int = 0) -> Bool {
        guard canEdit, let layer = activeLayer, !layer.isAdjustmentLayer, patterns.indices.contains(index),
              let src = CGImageSourceCreateWithData(patterns[index] as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let bitmap = PixelOps.bitmap(img) else { return false }
        let bytes = Self.tiled(bitmap, mask: selectionMask(), width: width, height: height)
        guard let picture = ContentAwareFill.image(bytes, width: width, height: height) else { return false }
        let local = Self.remap(picture, width: width, height: height, matrix(layer.transform).inverted()) ?? picture
        guard let data = PixelOps.png(local) else { return false }
        var stroke = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1)
        stroke.kind = "bitmap"; stroke.imageData = data
        mutateLayer("Fill with pattern") { $0.strokes.append(stroke) }
        return true
    }

    func removePattern(_ index: Int) { guard patterns.indices.contains(index) else { return }; patterns.remove(at: index); savePatterns() }
}

/// Edit menu entries: one per pattern, with its picture.
struct PatternMenu: View {
    @ObservedObject var studio: Studio
    var body: some View {
        Button(L("Define pattern")) { if !studio.definePattern() { studio.message = "Select an area up to 1024 × 1024 pixels first." } }
            .disabled(studio.selection == nil)
        Menu(L("Fill with pattern")) {
            ForEach(studio.patterns.indices, id: \.self) { i in
                Button { studio.fillWithPattern(i) } label: {
                    if let n = NSImage(data: studio.patterns[i]) { Image(nsImage: Self.thumb(n)) }
                    Text(LF("Pattern %d", i + 1))
                }
            }
            if !studio.patterns.isEmpty {
                Divider()
                Menu(L("Remove pattern")) { ForEach(studio.patterns.indices, id: \.self) { i in Button(LF("Pattern %d", i + 1)) { studio.removePattern(i) } } }
            }
        }.disabled(studio.patterns.isEmpty || !studio.canEdit)
    }
    static func thumb(_ n: NSImage) -> NSImage {
        let side = 18.0, k = side / max(n.size.width, n.size.height, 1)
        let out = NSImage(size: NSSize(width: max(1, n.size.width * k), height: max(1, n.size.height * k)))
        out.lockFocus(); n.draw(in: NSRect(origin: .zero, size: out.size)); out.unlockFocus()
        return out
    }
}
