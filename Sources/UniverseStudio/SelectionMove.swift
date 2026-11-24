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

/// Select → Transform selection: a frame around the selection whose edges and corners scale it,
/// whose inside moves it and which turns when dragged just outside (⇧ = 15° steps; the pixels stay).
/// ↩ or a click further out keeps it, Esc goes back.
///
/// The frame lives in its own unrotated space: `selectionFrame` is turned by `selectionAngle`
/// degrees around `selectionPivot` to land on the canvas.
extension Studio {
    var transformingSelection: Bool { selectionFrame != nil }

    func beginSelectionTransform() {
        guard let sel = selection else { return }
        let box = sel.bounds.standardized
        guard box.width >= 1, box.height >= 1 else { return }
        selectionFrameOriginal = (sel, box); selectionAngle = 0; selectionPivot = CGPoint(x: box.midX, y: box.midY); selectionFrame = box
    }

    /// Frame space → canvas.
    var selectionFrameTransform: CGAffineTransform { Self.rotation(selectionAngle, around: selectionPivot) }

    static func rotation(_ degrees: Double, around c: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: c.x, y: c.y).rotated(by: degrees * .pi / 180).translatedBy(x: -c.x, y: -c.y)
    }

    /// A canvas point in frame space (for hit tests and drags).
    func frameSpace(_ p: CGPoint) -> CGPoint { p.applying(selectionFrameTransform.inverted()) }

    /// `original` scaled from its box `from` into `to`, then turned by `angle` degrees around `pivot`.
    func scaledSelection(_ original: CanvasSelection, from o: CGRect, to r: CGRect, angle: Double = 0, pivot: CGPoint = .zero) -> CanvasSelection? {
        let sx = r.width / max(o.width, 0.001), sy = r.height / max(o.height, 0.001)
        let scale = CGAffineTransform(translationX: r.minX, y: r.minY).scaledBy(x: sx, y: sy).translatedBy(x: -o.minX, y: -o.minY)
        let t = scale.concatenating(Self.rotation(angle, around: pivot))
        if let mask = original.mask {
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            // Bitmap y runs up: flip into document space, transform, flip back.
            let flipMask = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: Double(mask.height))
            let flipDoc = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: Double(height))
            ctx.concatenate(flipMask.concatenating(t).concatenating(flipDoc))
            ctx.draw(mask, in: CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
            guard let moved = ctx.makeImage(), let bytes = PixelOps.grayBytes(moved), let box = PixelOps.bounds(bytes, width: width, height: height) else { return nil }
            return CanvasSelection(points: [box.origin, CGPoint(x: box.maxX, y: box.maxY)], mask: moved, maskData: PixelOps.png(moved))
        }
        var s = original
        if angle.truncatingRemainder(dividingBy: 360) != 0 && (original.ellipse || original.points.count == 2) {
            // Rectangles and ellipses are stored as two corners; turned, they become outlines.
            let b = original.bounds
            if original.ellipse {
                s.points = (0..<96).map { i in let a = Double(i) / 96 * 2 * .pi; return CGPoint(x: b.midX + cos(a) * b.width / 2, y: b.midY + sin(a) * b.height / 2) }
            } else { s.points = [b.origin, CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)] }
            s.ellipse = false
        }
        s.points = s.points.map { $0.applying(t) }
        return s
    }

    private func refreshTransformedSelection() {
        guard let (original, box) = selectionFrameOriginal, let r = selectionFrame else { return }
        if let s = scaledSelection(original, from: box, to: r, angle: selectionAngle, pivot: selectionPivot) { selection = s }
    }

    func updateSelectionFrame(_ r: CGRect) {
        guard selectionFrameOriginal != nil, r.width >= 1, r.height >= 1 else { return }
        selectionFrame = r
        refreshTransformedSelection()
    }

    /// Whether a canvas point is just outside the frame, where a drag turns it.
    func selectionRotateZone(_ p: CGPoint, tolerance t: Double) -> Bool {
        guard let r = selectionFrame else { return false }
        let q = frameSpace(p)
        return !r.insetBy(dx: -t, dy: -t).contains(q) && r.insetBy(dx: -3 * t, dy: -3 * t).contains(q)
    }

    /// Starts turning: the pivot moves to the frame's centre without moving anything on the canvas.
    func beginSelectionRotation() {
        guard let r = selectionFrame else { return }
        let c = CGPoint(x: r.midX, y: r.midY), world = c.applying(selectionFrameTransform)
        selectionFrame = r.offsetBy(dx: world.x - c.x, dy: world.y - c.y); selectionPivot = world
    }

    /// Sets the angle; `snap` rounds it to 15° steps.
    func rotateSelectionFrame(to degrees: Double, snap: Bool = false) {
        guard selectionFrame != nil else { return }
        var a = degrees.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 } else if a < -180 { a += 360 }
        selectionAngle = snap ? (a / 15).rounded() * 15 : a
        refreshTransformedSelection()
    }

    func applySelectionTransform() { selectionFrame = nil; selectionFrameOriginal = nil; selectionAngle = 0 }

    func cancelSelectionTransform() {
        if let (original, _) = selectionFrameOriginal { selection = original }
        selectionFrame = nil; selectionFrameOriginal = nil; selectionAngle = 0
    }
}
