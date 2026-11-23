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
