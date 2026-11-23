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

    /// Dragging to `p`; `square` keeps a new frame square (⇧). The frame stays on the canvas.
    func cropDrag(_ grab: CropGrab, to p: CGPoint, square: Bool = false) {
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        cropRect = Self.frameDrag(grab, to: p, square: square, within: canvas).intersection(canvas).integral
    }

    /// The frame after dragging `grab` to `p`; a moved frame stays inside `within` when given.
    static func frameDrag(_ grab: CropGrab, to p: CGPoint, square: Bool = false, within canvas: CGRect? = nil) -> CGRect {
        var r: CGRect
        switch grab {
        case .new(let a):
            var q = p
            if square { let s = max(abs(p.x - a.x), abs(p.y - a.y)); q = CGPoint(x: a.x + (p.x < a.x ? -s : s), y: a.y + (p.y < a.y ? -s : s)) }
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
