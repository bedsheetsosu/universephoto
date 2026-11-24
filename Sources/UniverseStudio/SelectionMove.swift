import CoreGraphics

/// Moving the selection's outline (not the pixels): drag inside it with a selection tool, or
/// nudge it with the arrow keys (⇧ = 10 px) while a selection tool is active.
extension Studio {
    /// Whether `p` (document pixels) lies inside the current selection.
    func selectionContains(_ p: CGPoint) -> Bool {
        guard let sel = selection, CGRect(x: 0, y: 0, width: width, height: height).contains(p) else { return false }
        if sel.mask != nil {
            guard let m = selectionMask() else { return false }
            return m[Int(p.y) * width + Int(p.x)] >= 128
        }
        let path = CGMutablePath()
        if sel.ellipse { path.addEllipse(in: sel.bounds) } else if sel.points.count == 2 { path.addRect(sel.bounds) }
        else if let f = sel.points.first { path.move(to: f); sel.points.dropFirst().forEach { path.addLine(to: $0) }; path.closeSubpath() }
        return path.contains(p)
    }

    /// `original` moved by `d` (pixel masks are shifted, shapes have their points moved).
    func movedSelection(_ original: CanvasSelection, by d: CGPoint) -> CanvasSelection? {
        let dx = d.x.rounded(), dy = d.y.rounded()
        if let mask = original.mask {
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            // Bitmap y runs up: a move down in document pixels is negative here.
            ctx.draw(mask, in: CGRect(x: dx, y: -dy, width: Double(mask.width), height: Double(mask.height)))
            guard let moved = ctx.makeImage(), let bytes = PixelOps.grayBytes(moved), let box = PixelOps.bounds(bytes, width: width, height: height) else { return nil }
            return CanvasSelection(points: [box.origin, CGPoint(x: box.maxX, y: box.maxY)], mask: moved, maskData: PixelOps.png(moved))
        }
        var s = original
        s.points = original.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return s
    }

    func nudgeSelection(dx: Double, dy: Double) {
        guard let sel = selection, let moved = movedSelection(sel, by: CGPoint(x: dx, y: dy)) else { return }
        selection = moved
    }
}

/// Select → Transform selection: a frame around the selection whose edges and corners scale it
/// and whose inside moves it (the pixels stay). ↩ or a click outside keeps it, Esc goes back.
extension Studio {
    var transformingSelection: Bool { selectionFrame != nil }

    func beginSelectionTransform() {
        guard let sel = selection else { return }
        let box = sel.bounds.standardized
        guard box.width >= 1, box.height >= 1 else { return }
        selectionFrameOriginal = (sel, box); selectionFrame = box
    }

    /// `original` scaled from its box `from` into `to`.
    func scaledSelection(_ original: CanvasSelection, from o: CGRect, to r: CGRect) -> CanvasSelection? {
        let sx = r.width / max(o.width, 0.001), sy = r.height / max(o.height, 0.001)
        let t = CGAffineTransform(translationX: r.minX, y: r.minY).scaledBy(x: sx, y: sy).translatedBy(x: -o.minX, y: -o.minY)
        if let mask = original.mask {
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            let R = CGRect(x: 0, y: 0, width: mask.width, height: mask.height).applying(t)
            ctx.draw(mask, in: CGRect(x: R.minX, y: Double(height) - R.maxY, width: R.width, height: R.height))   // bitmap y runs up
            guard let moved = ctx.makeImage(), let bytes = PixelOps.grayBytes(moved), let box = PixelOps.bounds(bytes, width: width, height: height) else { return nil }
            return CanvasSelection(points: [box.origin, CGPoint(x: box.maxX, y: box.maxY)], mask: moved, maskData: PixelOps.png(moved))
        }
        var s = original
        s.points = original.points.map { $0.applying(t) }
        return s
    }

    func updateSelectionFrame(_ r: CGRect) {
        guard let (original, box) = selectionFrameOriginal, r.width >= 1, r.height >= 1 else { return }
        selectionFrame = r
        if let s = scaledSelection(original, from: box, to: r) { selection = s }
    }

    func applySelectionTransform() { selectionFrame = nil; selectionFrameOriginal = nil }

    func cancelSelectionTransform() {
        if let (original, _) = selectionFrameOriginal { selection = original }
        selectionFrame = nil; selectionFrameOriginal = nil
    }
}
