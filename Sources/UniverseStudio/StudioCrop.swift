import CoreGraphics

/// The crop tool: drag a frame, adjust it by its corners and edges or move it, ↩ crops, Esc cancels.
enum CropGrab: Equatable, Sendable {
    case new(CGPoint)                 // fresh frame from this corner
    case move(CGRect, CGPoint)        // frame and press point at the start
    case edge(left: Bool, right: Bool, top: Bool, bottom: Bool, CGRect)
}

extension Studio {
    /// What a press at `p` (document pixels) grabs; `tolerance` is the handle radius in pixels.
    func cropPress(at p: CGPoint, tolerance t: Double) -> CropGrab { Self.frameGrab(cropRect, at: p, tolerance: t) }

    /// What a press grabs on a frame: an edge or corner, the inside, or (outside) a new frame.
    static func frameGrab(_ rect: CGRect?, at p: CGPoint, tolerance t: Double) -> CropGrab {
        guard let r = rect else { return .new(p) }
        let l = abs(p.x - r.minX) <= t, rr = abs(p.x - r.maxX) <= t, top = abs(p.y - r.minY) <= t, b = abs(p.y - r.maxY) <= t
        let withinX = p.x >= r.minX - t && p.x <= r.maxX + t, withinY = p.y >= r.minY - t && p.y <= r.maxY + t
        if (l || rr) && withinY || (top || b) && withinX {
            return .edge(left: l && withinY, right: rr && withinY && !l, top: top && withinX, bottom: b && withinX && !top, r)
        }
        if r.contains(p) { return .move(r, p) }
        return .new(p)
    }

    enum CropRatio: String, CaseIterable, Identifiable {
        case free, square, r4x3, r3x2, r16x9, original
        var id: String { rawValue }
        var title: String { switch self { case .free: "Free"; case .square: "1:1"; case .r4x3: "4:3"; case .r3x2: "3:2"; case .r16x9: "16:9"; case .original: "Original" } }
    }

    /// Width ÷ height the crop frame keeps, nil = free (⇧ makes a free frame square).
    func cropAspect(shift: Bool = false) -> Double? {
        let base: Double?
        switch cropRatio {
        case .free: base = shift ? 1 : nil
        case .square: base = 1
        case .r4x3: base = 4.0 / 3
        case .r3x2: base = 3.0 / 2
        case .r16x9: base = 16.0 / 9
        case .original: base = Double(width) / Double(max(1, height))
        }
        guard let b = base else { return nil }
        return cropPortrait && b != 1 ? 1 / b : b
    }

    /// Dragging to `p`; `square` (⇧) keeps a free frame square. The frame stays on the canvas.
    func cropDrag(_ grab: CropGrab, to p: CGPoint, square: Bool = false) {
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        let aspect = cropAspect(shift: square)
        var r = Self.frameDrag(grab, to: p, ratio: aspect, within: canvas)
        if !canvas.contains(r) { r = r.intersection(canvas); if let a = aspect { r = Self.fit(a, in: r) } }
        cropRect = r.integral
    }

    /// The biggest rectangle of ratio `a` centred in `r`.
    static func fit(_ a: Double, in r: CGRect) -> CGRect {
        guard r.width > 0, r.height > 0 else { return r }
        let w = min(r.width, r.height * a), h = w / a
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    /// Picking a ratio refits an open frame (centred, as big as fits in it).
    func applyCropRatio() {
        guard let r = cropRect, let a = cropAspect() else { return }
        cropRect = Self.fit(a, in: r).integral
    }

    /// The frame after dragging `grab` to `p`; a moved frame stays inside `within` when given.
    /// `ratio` (width ÷ height) keeps the frame's proportions; `square` is ratio 1.
    static func frameDrag(_ grab: CropGrab, to p: CGPoint, square: Bool = false, ratio: Double? = nil, within canvas: CGRect? = nil) -> CGRect {
        let ratio = ratio ?? (square ? 1 : nil)
        var r: CGRect
        switch grab {
        case .new(let a):
            var q = p
            if let k = ratio {
                let w = max(abs(p.x - a.x), abs(p.y - a.y) * k), h = w / k
                q = CGPoint(x: a.x + (p.x < a.x ? -w : w), y: a.y + (p.y < a.y ? -h : h))
            }
            r = CGRect(x: min(a.x, q.x), y: min(a.y, q.y), width: abs(q.x - a.x), height: abs(q.y - a.y))
        case .move(let start, let a):
            r = start.offsetBy(dx: p.x - a.x, dy: p.y - a.y)
            if let canvas {
                r.origin.x = min(max(canvas.minX, r.origin.x), canvas.maxX - r.width)
                r.origin.y = min(max(canvas.minY, r.origin.y), canvas.maxY - r.height)
            }
        case .edge(let l, let rt, let t, let b, let s):
            var x0 = s.minX, x1 = s.maxX, y0 = s.minY, y1 = s.maxY
            if l { x0 = p.x }; if rt { x1 = p.x }; if t { y0 = p.y }; if b { y1 = p.y }
            if let k = ratio {
                let horizontal = l || rt, vertical = t || b
                if horizontal {
                    // Width from the dragged side; height follows, from the fixed edge for a corner, centred for a side.
                    let h = abs(x1 - x0) / k
                    if vertical { if t { y0 = y1 - h } else { y1 = y0 + h } } else { y0 = s.midY - h / 2; y1 = s.midY + h / 2 }
                } else if vertical {
                    let w = abs(y1 - y0) * k
                    x0 = s.midX - w / 2; x1 = s.midX + w / 2
                }
            }
            r = CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
        }
        return r
    }

    /// ↩ / Apply: crops the document to the frame.
    func applyCrop() {
        guard let r = cropRect, r.width >= 1, r.height >= 1 else { cropRect = nil; return }
        cropRect = nil
        crop(to: r)
    }
}
