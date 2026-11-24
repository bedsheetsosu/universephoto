import UIKit
import TafelKit

/// Draws the perspective or ellipse aid (the canvas handles touches). Thin and translucent so
/// the picture stays readable.
final class GuideView: UIView {
    enum Content: Equatable {
        case none
        case perspective(PerspectiveGuide)
        case ellipse(EllipseGuide)
    }

    var content: Content = .none { didSet { if content != oldValue { setNeedsDisplay() } } }
    var accent: UIColor = .systemTeal { didSet { setNeedsDisplay() } }
    /// The hovering Pencil is on the ellipse's band: its outline is drawn bolder.
    var highlight = false { didSet { if highlight != oldValue { setNeedsDisplay() } } }
    /// Perspective line the current stroke follows (drawn bright while drawing).
    var activeLine: SnapLine? { didSet { if activeLine != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        switch content {
        case .none: break
        case .perspective(let g): drawPerspective(g)
        case .ellipse(let e): drawEllipse(e)
        }
    }

    private func knob(_ p: CGPoint) {
        let r: CGFloat = 11
        let c = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        UIColor.black.withAlphaComponent(0.45).setFill()
        c.fill()
        accent.setStroke()
        c.lineWidth = 2.5
        c.stroke()
        let dot = UIBezierPath(ovalIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
        accent.setFill()
        dot.fill()
    }

    private func drawPerspective(_ g: PerspectiveGuide) {
        let reach = 2 * max(bounds.width, bounds.height) + 2000
        let rays = UIBezierPath()
        for v in g.points {
            for i in 0..<36 {
                let a = Double(i) * .pi / 18
                rays.move(to: v)
                rays.addLine(to: CGPoint(x: v.x + cos(a) * reach, y: v.y + sin(a) * reach))
            }
        }
        accent.withAlphaComponent(0.16).setStroke()
        rays.lineWidth = 1
        rays.stroke()
        // Horizon through the first two points (or a level line through a single one).
        if let a = g.points.first {
            let b = g.points.count >= 2 ? g.points[1] : CGPoint(x: a.x + 1, y: a.y)
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 1)
            let horizon = UIBezierPath()
            horizon.move(to: CGPoint(x: a.x - dx / len * reach, y: a.y - dy / len * reach))
            horizon.addLine(to: CGPoint(x: a.x + dx / len * reach, y: a.y + dy / len * reach))
            accent.withAlphaComponent(0.55).setStroke()
            horizon.lineWidth = 1.5
            horizon.setLineDash([8, 6], count: 2, phase: 0)
            horizon.stroke()
        }
        if let l = activeLine {
            let a = CGPoint(x: l.origin.x - l.direction.x * reach, y: l.origin.y - l.direction.y * reach)
            let b = CGPoint(x: l.origin.x + l.direction.x * reach, y: l.origin.y + l.direction.y * reach)
            let p = UIBezierPath()
            p.move(to: a); p.addLine(to: b)
            accent.withAlphaComponent(0.9).setStroke()
            p.lineWidth = 1.5
            p.stroke()
        }
        g.points.forEach(knob)
    }

    private func drawEllipse(_ e: EllipseGuide) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.translateBy(x: e.center.x, y: e.center.y)
        ctx.rotate(by: e.angle)
        let outer = EllipseGuide.snapDistance
        let band = UIBezierPath(ovalIn: CGRect(x: -e.rx - outer, y: -e.ry - outer, width: 2 * (e.rx + outer), height: 2 * (e.ry + outer)))
        band.append(UIBezierPath(ovalIn: CGRect(x: -e.rx + outer, y: -e.ry + outer,
                                                width: max(2 * (e.rx - outer), 0), height: max(2 * (e.ry - outer), 0))))
        band.usesEvenOddFillRule = true
        UIColor.white.withAlphaComponent(0.08).setFill()
        band.fill()
        let line = UIBezierPath(ovalIn: CGRect(x: -e.rx, y: -e.ry, width: 2 * e.rx, height: 2 * e.ry))
        accent.withAlphaComponent(highlight ? 1 : 0.85).setStroke()
        line.lineWidth = highlight ? 3 : 1.5
        line.stroke()
        let axes = UIBezierPath()
        axes.move(to: CGPoint(x: -e.rx, y: 0)); axes.addLine(to: CGPoint(x: e.rx, y: 0))
        axes.move(to: CGPoint(x: 0, y: -e.ry)); axes.addLine(to: CGPoint(x: 0, y: e.ry))
        UIColor.white.withAlphaComponent(0.25).setStroke()
        axes.lineWidth = 1
        axes.setLineDash([4, 5], count: 2, phase: 0)
        axes.stroke()
        ctx.restoreGState()
        e.handles.forEach(knob)
    }
}
