import AppKit
import UniformTypeIdentifiers

/// Exporting layers one by one, and the selection as its own picture.
extension Studio {
    /// File-system safe name ("/", ":" and control characters removed, never empty).
    static func fileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Layer" : String(cleaned.prefix(80))
    }

    /// Every pixel layer as its own PNG (document size, transform, style and adjustments applied;
    /// opacity and blend mode left out so the file is the layer itself). Returns the written files.
    @discardableResult
    func exportLayers(to directory: URL, onlyVisible: Bool = true) throws -> [URL] {
        var written: [URL] = []
        let layers = composite(self.layers)
        for (i, layer) in layers.enumerated() where !layer.isAdjustmentLayer && (!onlyVisible || layer.visible) {
            var solo = layer; solo.opacity = 1; solo.blend = .normal; solo.visible = true; solo.clipped = false
            guard let image = Renderer.render(layers: [solo], width: width, height: height) else { continue }
            let url = directory.appendingPathComponent(String(format: "%02d %@.png", i + 1, Self.fileName(layer.name)))
            try ImageFiles.export(image: image, url: url, type: .png)
            written.append(url)
        }
        return written
    }

    /// Everything visible inside the selection's box, cropped to it.
    func selectionImage() -> CGImage? {
        guard let sel = selection, let full = Renderer.render(layers: composite(layers), width: width, height: height) else { return nil }
        let box = sel.bounds.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !box.isEmpty, let ctx = Renderer.context(width: Int(box.width), height: Int(box.height)) else { return nil }
        ctx.translateBy(x: -box.minX, y: -box.minY)
        if let mask = selectionMask(), let m = PixelOps.grayImage(mask, width: width, height: height) {
            // Pixel and shape selections: only what is selected (soft edges stay soft).
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
            ctx.clip(to: CGRect(x: 0, y: 0, width: width, height: height), mask: m)
            ctx.scaleBy(x: 1, y: -1); ctx.translateBy(x: 0, y: -CGFloat(height))
            Renderer.drawImage(full, in: ctx, rect: CGRect(x: 0, y: 0, width: width, height: height))
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    func exportLayersPanel() {
        let p = NSOpenPanel(); p.title = L("Export layers as files"); p.prompt = L("Export")
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        guard p.runModal() == .OK, let dir = p.url else { return }
        do { let files = try exportLayers(to: dir); message = LF("%d layers exported", files.count) } catch { report(error) }
    }

    func exportSelectionPanel() {
        guard let image = selectionImage() else { return }
        let p = NSSavePanel(); p.title = L("Export selection"); p.prompt = L("Export"); p.allowedContentTypes = [.png]; p.nameFieldStringValue = title + " " + L("Selection")
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try ImageFiles.export(image: image, url: url, type: .png) } catch { report(error) }
    }
}

extension Studio {
    /// Indices of layers whose name or group matches, or that are text / adjustment / hidden layers when asked so.
    func layerMatches(_ query: String) -> [Int] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(layers.indices) }
        return layers.indices.filter { i in
            let l = layers[i]
            if l.name.lowercased().contains(q) || (group(of: l)?.name.lowercased().contains(q) ?? false) { return true }
            let kinds = [(["text", L("Text").lowercased()], l.strokes.contains { $0.kind == "text" }),
                         (["adjustment", L("Adjustment").lowercased()], l.isAdjustmentLayer),
                         (["hidden", L("Hidden").lowercased()], !l.visible)]
            return kinds.contains { words, hit in hit && words.contains { $0.hasPrefix(q) } }
        }
    }
}
