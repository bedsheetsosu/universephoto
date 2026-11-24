import UIKit

/// Drawn on the iPad above the Mac picture, so the Pencil feels direct although the real stroke
/// arrives a few frames later:
/// - instant ink: a thin trail behind the Pencil tip that disappears after about the measured
///   picture delay – right when the Mac's own stroke shows up underneath;
/// - hover dot: a small ring under the hovering tip (the Mac cursor in the video lags behind).
/// Purely local; nothing of this is sent to the Mac.
final class InkOverlayView: UIView {
    private struct Point {
        var p: CGPoint
        var width: CGFloat
        var time: CFTimeInterval
        var startsStroke: Bool
    }

    var color: UIColor = .white
    /// How long a point stays visible (seconds); set from the measured picture delay.
    var lifetime: CFTimeInterval = 0.12

    private var points: [Point] = []
    private var hover: CGPoint?
    /// Diameter of the hover ring.
    var hoverSize: CGFloat = 10
    /// Tilt of the hovering Pencil (direction × amount 0…1), drawn as a short line from the dot.
    var hoverTilt: CGVector?
    private var link: CADisplayLink?
    private var dirty = CGRect.null

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Input

    func add(_ p: CGPoint, pressure: Double, newStroke: Bool) {
        points.append(Point(p: p, width: 1.2 + 3.2 * CGFloat(min(max(pressure, 0), 1)), time: CACurrentMediaTime(),
                            startsStroke: newStroke || points.isEmpty))
        mark(p, radius: 6)
        startLink()
    }

    func setHover(_ p: CGPoint?) {
        let r = hoverSize / 2 + 4 + (hoverTilt == nil ? 0 : 30)
        if let h = hover { mark(h, radius: r) }
        hover = p
        if let p { mark(p, radius: r) }
        flush()
    }

    func clear() {
        points.removeAll()
        hover = nil
        dirty = bounds
        flush()
    }

    // MARK: Drawing

    private func mark(_ p: CGPoint, radius: CGFloat) {
        dirty = dirty.union(CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
    }

    private func flush() {
        guard !dirty.isNull else { return }
        setNeedsDisplay(dirty.insetBy(dx: -2, dy: -2))
        dirty = .null
    }

    private func startLink() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        // Everything currently drawn is dirty (it fades), then old points go.
        for pt in points { mark(pt.p, radius: 6) }
        points.removeAll { now - $0.time > lifetime }
        if points.isEmpty { link?.invalidate(); link = nil }
        flush()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let now = CACurrentMediaTime()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        var prev: Point?
        for pt in points {
            defer { prev = pt }
            guard let a = prev, !pt.startsStroke else { continue }
            // Fades towards the tail, so the hand-over to the Mac's stroke is soft.
            let age = (now - pt.time) / max(lifetime, 0.01)
            let alpha = CGFloat(max(0, 1 - age)) * 0.85
            guard alpha > 0.01 else { continue }
            ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth((a.width + pt.width) / 2)
            ctx.move(to: a.p)
            ctx.addLine(to: pt.p)
            ctx.strokePath()
        }
        if let h = hover {
            let r = CGRect(x: h.x - hoverSize / 2, y: h.y - hoverSize / 2, width: hoverSize, height: hoverSize)
            ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: r)
            ctx.setStrokeColor(color.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: r)
            if let t = hoverTilt, hypot(t.dx, t.dy) > 0.05 {
                // The tip leans away from where the Pencil's body points.
                let end = CGPoint(x: h.x - t.dx * 30, y: h.y - t.dy * 30)
                ctx.move(to: h); ctx.addLine(to: end)
                ctx.setStrokeColor(color.withAlphaComponent(0.8).cgColor)
                ctx.setLineWidth(2)
                ctx.strokePath()
            }
        }
    }
}
