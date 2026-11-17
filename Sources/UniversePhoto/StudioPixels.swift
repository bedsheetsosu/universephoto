import AppKit
import CoreGraphics

/// Pixel tools of the studio: paint bucket, magic wand, mask selections, rasterize.
extension Studio {
    enum SelectionCombine { case replace, add, subtract }

    /// What the bucket and the wand look at: the active layer alone, or everything visible.
    func sampledImage(merged: Bool) -> CGImage? {
        if merged { return Renderer.render(layers: layers, width: width, height: height) }
        guard var layer = activeLayer else { return nil }
        // The layer's own pixels in its own coordinates (no opacity, blend, transform).
        layer.opacity = 1; layer.blend = .normal; layer.transform = .init(); layer.visible = true
        return Renderer.render(layers: [layer], width: width, height: height)
    }

    /// Region a click at `point` (document or layer pixels, y down) would take.
    func region(at point: CGPoint, merged: Bool) -> [UInt8]? {
        guard let image = sampledImage(merged: merged), let bitmap = PixelOps.bitmap(image) else { return nil }
        return PixelOps.similarRegion(in: bitmap, seed: (Int(point.x.rounded(.down)), Int(point.y.rounded(.down))),
                                      tolerance: Int(tolerance), contiguous: contiguous)
    }

    /// Paint bucket: fills the similar region with the foreground colour as a bitmap stroke.
    /// The current selection still limits it (the caller puts it on the stroke).
    func bucketStroke(at layerPoint: CGPoint, documentPoint: CGPoint) -> InkStroke? {
        guard let mask = region(at: sampleMerged ? documentPoint : layerPoint, merged: sampleMerged) else { return nil }
        let grown = PixelOps.grow(mask, width: width, height: height)
        var c = color; c.alpha *= brushOpacity
        guard let image = PixelOps.fillImage(grown, width: width, height: height, color: c), let data = PixelOps.png(image) else { return nil }
        var stroke = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: c, width: 1)
        stroke.kind = "bitmap"; stroke.imageData = data
        return stroke
    }

    /// Magic wand: selects the similar region; Shift adds to, Option subtracts from the selection.
    func magicWand(at point: CGPoint, combine: SelectionCombine) {
        guard let picked = region(at: point, merged: sampleMerged) else { return }
        var mask = picked
        if combine != .replace, let current = selectionMask() {
            for i in mask.indices { mask[i] = combine == .add ? max(current[i], picked[i]) : (picked[i] != 0 ? 0 : current[i]) }
        }
        setSelection(mask: mask)
    }

    /// The current selection as a mask (shapes are rasterized), nil without a selection.
    func selectionMask() -> [UInt8]? {
        guard let sel = selection else { return nil }
        if let m = sel.mask { return PixelOps.grayBytes(m) }
        let p = CGMutablePath()
        if sel.ellipse { p.addEllipse(in: sel.bounds) } else if sel.points.count == 2 { p.addRect(sel.bounds) }
        else if let first = sel.points.first { p.move(to: first); sel.points.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath() }
        return PixelOps.mask(for: p, width: width, height: height)
    }

    func setSelection(mask: [UInt8]) {
        guard let box = PixelOps.bounds(mask, width: width, height: height), let image = PixelOps.grayImage(mask, width: width, height: height) else {
            selection = nil; return
        }
        selection = CanvasSelection(points: [box.origin, CGPoint(x: box.maxX, y: box.maxY)], mask: image, maskData: PixelOps.png(image))
    }

    func selectAll() { selection = CanvasSelection(points: [.zero, CGPoint(x: width, y: height)]) }

    func invertSelection() {
        guard let mask = selectionMask() else { selectAll(); return }
        setSelection(mask: mask.map { 255 - $0 })
    }

    /// Bakes the layer's strokes and picture into one picture (masks and adjustments stay live).
    func rasterizeLayer() {
        guard var layer = activeLayer, !layer.locked, !layer.strokes.isEmpty else { return }
        layer.opacity = 1; layer.blend = .normal; layer.transform = .init(); layer.visible = true; layer.mask = nil; layer.adjustment = .init()
        guard let image = Renderer.render(layers: [layer], width: width, height: height), let data = try? Renderer.png(image) else { return }
        mutateLayer("Rasterize layer") { $0.imageData = data; $0.strokes = [] }
    }
}
