import CoreGraphics
import Foundation

/// The pen tool's path: anchors with an optional out-handle (the in-handle mirrors it, like a
/// smooth Bézier point). Clicks add corner points, click-and-drag pulls out curve handles.
struct PenPath: Equatable, Sendable {
    struct Node: Equatable, Sendable { var anchor: CGPoint; var out: CGPoint? }
    var nodes: [Node] = []
    var closed = false

    /// Mirror of the out-handle through the anchor.
    static func inHandle(_ n: Node) -> CGPoint { n.out.map { CGPoint(x: 2 * n.anchor.x - $0.x, y: 2 * n.anchor.y - $0.y) } ?? n.anchor }

    var cgPath: CGPath {
        let p = CGMutablePath()
        guard let first = nodes.first else { return p }
        p.move(to: first.anchor)
        func segment(_ a: Node, _ b: Node) {
            if a.out == nil && b.out == nil { p.addLine(to: b.anchor) }
            else { p.addCurve(to: b.anchor, control1: a.out ?? a.anchor, control2: Self.inHandle(b)) }
        }
        for (a, b) in zip(nodes, nodes.dropFirst()) { segment(a, b) }
        if closed, nodes.count > 2 { segment(nodes[nodes.count - 1], first); p.closeSubpath() }
        return p
    }

    /// Points along the path every few pixels (for a selection).
    func flattened(step: Double = 2) -> [CGPoint] {
        var out: [CGPoint] = []
        func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint) {
            let len = hypot(c1.x - p0.x, c1.y - p0.y) + hypot(c2.x - c1.x, c2.y - c1.y) + hypot(p3.x - c2.x, p3.y - c2.y)
            let n = max(1, Int(len / step))
            for k in 1...n {
                let t = Double(k) / Double(n), u = 1 - t
                out.append(CGPoint(x: u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x,
                                   y: u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y))
            }
        }
        guard let first = nodes.first else { return [] }
        out.append(first.anchor)
        var pairs = Array(zip(nodes, nodes.dropFirst()))
        if closed, nodes.count > 2 { pairs.append((nodes[nodes.count - 1], first)) }
        for (a, b) in pairs { cubic(a.anchor, a.out ?? a.anchor, Self.inHandle(b), b.anchor) }
        return out
    }

    /// As stroke points: anchor, then out-handle (the anchor again when there is none).
    var encoded: [InkPoint] { nodes.flatMap { [InkPoint(x: $0.anchor.x, y: $0.anchor.y, pressure: 1), InkPoint(x: ($0.out ?? $0.anchor).x, y: ($0.out ?? $0.anchor).y, pressure: 1)] } }

    init(nodes: [Node] = [], closed: Bool = false) { self.nodes = nodes; self.closed = closed }

    init(encoded points: [InkPoint], closed: Bool) {
        nodes = stride(from: 0, to: points.count - 1, by: 2).map { i in
            let a = CGPoint(x: points[i].x, y: points[i].y), o = CGPoint(x: points[i + 1].x, y: points[i + 1].y)
            return Node(anchor: a, out: hypot(o.x - a.x, o.y - a.y) < 0.01 ? nil : o)
        }
        self.closed = closed
    }

    /// The path moved through `m` (document → layer coordinates).
    func applying(_ m: CGAffineTransform) -> PenPath {
        PenPath(nodes: nodes.map { Node(anchor: $0.anchor.applying(m), out: $0.out?.applying(m)) }, closed: closed)
    }
}

extension Studio {
    /// Pen tool click (document pixels): closes the path on its first point, else adds a point.
    /// Returns the index of the node a following drag should pull handles out of (nil when closing).
    func penClick(at p: CGPoint, closeDistance: Double) -> Int? {
        var path = penPath ?? PenPath()
        if path.closed { path = PenPath() }
        if let first = path.nodes.first, path.nodes.count > 2, hypot(p.x - first.anchor.x, p.y - first.anchor.y) <= closeDistance {
            path.closed = true; penPath = path; return nil
        }
        path.nodes.append(.init(anchor: p, out: nil)); penPath = path
        return path.nodes.count - 1
    }

    /// Dragging after a click pulls the out-handle (the in-handle mirrors it).
    func penDrag(node i: Int, to p: CGPoint) {
        guard var path = penPath, path.nodes.indices.contains(i) else { return }
        let a = path.nodes[i].anchor
        path.nodes[i].out = hypot(p.x - a.x, p.y - a.y) < 2 ? nil : p
        penPath = path
    }

    /// The path as a stroke on the active layer: filled with the colour, or traced with the brush size.
    func commitPath(fill: Bool) {
        guard let path = penPath, path.nodes.count >= 2, canEdit, let layer = activeLayer, !layer.isAdjustmentLayer else { return }
        let local = path.applying(matrix(layer.transform).inverted())
        var c = color; c.alpha *= brushOpacity
        var stroke = InkStroke(points: local.encoded, color: c, width: max(1, brushSize))
        stroke.kind = "path"; stroke.filled = fill ? true : nil; stroke.pathClosed = path.closed ? true : nil
        add(stroke)
    }

    /// The path becomes the selection (an open path is closed with a straight line).
    func pathToSelection() {
        guard let path = penPath, path.nodes.count >= 3 else { return }
        var closed = path; closed.closed = true
        selection = CanvasSelection(points: closed.flattened())
    }
}
