import CoreGraphics
import Foundation

/// The pen tool's path: anchors with an optional out-handle; the in-handle mirrors it (a smooth
/// Bézier point) unless it has been set on its own (`inH`, after ⌥-dragging a handle or inserting
/// a point). Clicks add corner points, click-and-drag pulls out curve handles.
struct PenPath: Equatable, Sendable {
    struct Node: Equatable, Sendable { var anchor: CGPoint; var out: CGPoint?; var inH: CGPoint? = nil }
    var nodes: [Node] = []
    var closed = false

    /// The in-handle: its own when set, else the out-handle mirrored through the anchor.
    static func inHandle(_ n: Node) -> CGPoint { n.inH ?? n.out.map { CGPoint(x: 2 * n.anchor.x - $0.x, y: 2 * n.anchor.y - $0.y) } ?? n.anchor }

    /// Segments as (from, to) node index pairs, the closing one included.
    var segments: [(Int, Int)] {
        var s = (0..<max(0, nodes.count - 1)).map { ($0, $0 + 1) }
        if closed, nodes.count > 2 { s.append((nodes.count - 1, 0)) }
        return s
    }

    /// Control points of segment `k` (anchor, out, in, anchor).
    func controls(_ k: Int) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        let (i, j) = segments[k], a = nodes[i], b = nodes[j]
        return (a.anchor, a.out ?? a.anchor, Self.inHandle(b), b.anchor)
    }

    static func point(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * u * c.0.x + 3 * u * u * t * c.1.x + 3 * u * t * t * c.2.x + t * t * t * c.3.x,
                       y: u * u * u * c.0.y + 3 * u * u * t * c.1.y + 3 * u * t * t * c.2.y + t * t * t * c.3.y)
    }

    /// The segment and position on it closest to `p`, if within `tolerance`.
    func segmentHit(_ p: CGPoint, tolerance: Double) -> (segment: Int, t: Double)? {
        var best: (Int, Double, Double)?
        for k in segments.indices {
            let c = controls(k)
            for n in 1..<100 {
                let t = Double(n) / 100, q = Self.point(c, t), d = hypot(q.x - p.x, q.y - p.y)
                if d <= tolerance, d < (best?.2 ?? .infinity) { best = (k, t, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Splits segment `k` at `t` (de Casteljau): the curve keeps its shape, the new point sits
    /// between, and returns its index.
    @discardableResult mutating func insert(segment k: Int, t: Double) -> Int {
        let (i, j) = segments[k], c = controls(k)
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        let p01 = lerp(c.0, c.1), p12 = lerp(c.1, c.2), p23 = lerp(c.2, c.3)
        let p012 = lerp(p01, p12), p123 = lerp(p12, p23), mid = lerp(p012, p123)
        let straight = nodes[i].out == nil && Self.inHandle(nodes[j]) == nodes[j].anchor
        // Freeze the neighbours' other handles before their handles on this segment change.
        if nodes[i].out != nil || !straight { nodes[i].inH = Self.inHandle(nodes[i]); nodes[i].out = p01 }
        if !straight { nodes[j].inH = p23 }
        if nodes[i].inH == nodes[i].anchor { nodes[i].inH = nil }
        let node = straight ? Node(anchor: mid, out: nil) : Node(anchor: mid, out: p123, inH: p012)
        let at = j == 0 ? nodes.count : j
        nodes.insert(node, at: at)
        return at
    }

    /// Whether any node has its own in-handle (then strokes store three points per node).
    var hasOwnInHandles: Bool { nodes.contains { $0.inH != nil } }

    var cgPath: CGPath {
        let p = CGMutablePath()
        guard let first = nodes.first else { return p }
        p.move(to: first.anchor)
        func segment(_ a: Node, _ b: Node) {
            if a.out == nil && Self.inHandle(b) == b.anchor { p.addLine(to: b.anchor) }
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

    /// As stroke points: anchor, then out-handle (the anchor again when there is none), and with
    /// own in-handles a third point per node (the in-handle as drawn).
    var encoded: [InkPoint] {
        let triples = hasOwnInHandles
        func ip(_ p: CGPoint) -> InkPoint { InkPoint(x: p.x, y: p.y, pressure: 1) }
        return nodes.flatMap { n in [ip(n.anchor), ip(n.out ?? n.anchor)] + (triples ? [ip(Self.inHandle(n))] : []) }
    }

    init(nodes: [Node] = [], closed: Bool = false) { self.nodes = nodes; self.closed = closed }

    init(encoded points: [InkPoint], closed: Bool, triples: Bool = false) {
        let step = triples ? 3 : 2
        nodes = stride(from: 0, to: points.count - (step - 1), by: step).map { i in
            let a = CGPoint(x: points[i].x, y: points[i].y), o = CGPoint(x: points[i + 1].x, y: points[i + 1].y)
            var n = Node(anchor: a, out: hypot(o.x - a.x, o.y - a.y) < 0.01 ? nil : o)
            if triples {
                let h = CGPoint(x: points[i + 2].x, y: points[i + 2].y)
                if hypot(h.x - Self.inHandle(n).x, h.y - Self.inHandle(n).y) > 0.01 { n.inH = h }
            }
            return n
        }
        self.closed = closed
    }

    /// The path moved through `m` (document → layer coordinates).
    func applying(_ m: CGAffineTransform) -> PenPath {
        PenPath(nodes: nodes.map { Node(anchor: $0.anchor.applying(m), out: $0.out?.applying(m), inH: $0.inH?.applying(m)) }, closed: closed)
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
    /// While a finished path is reopened (`editingPath`), this switches it between fill and
    /// stroke and takes the current colour and size instead of adding a new one.
    func commitPath(fill: Bool) {
        guard let path = penPath, path.nodes.count >= 2, canEdit, let layer = activeLayer, !layer.isAdjustmentLayer else { return }
        let local = path.applying(matrix(layer.transform).inverted())
        var c = color; c.alpha *= brushOpacity
        var stroke = InkStroke(points: local.encoded, color: c, width: max(1, brushSize))
        if let id = editingPath, let i = layer.strokes.firstIndex(where: { $0.id == id }) { stroke.id = layer.strokes[i].id }
        stroke.kind = "path"; stroke.filled = fill ? true : nil; stroke.pathClosed = path.closed ? true : nil
        stroke.pathTriples = local.hasOwnInHandles ? true : nil
        if let id = editingPath, let i = layer.strokes.firstIndex(where: { $0.id == id }) {
            mutateLayer("Edit path") { $0.strokes[i] = stroke }
        } else {
            add(stroke)
        }
    }

    /// A finished path (filled or stroked) on the active layer under `p` (document pixels).
    func pathStroke(at p: CGPoint, tolerance: Double) -> InkStroke? {
        guard let layer = activeLayer else { return nil }
        let local = p.applying(matrix(layer.transform).inverted())
        return layer.strokes.reversed().first { s in
            guard s.kind == "path" else { return false }
            let path = PenPath(encoded: s.points, closed: s.pathClosed == true, triples: s.pathTriples == true).cgPath
            if s.filled == true { return path.contains(local) }
            return path.copy(strokingWithWidth: max(s.width, 2 * tolerance), lineCap: .round, lineJoin: .round, miterLimit: 10).contains(local)
        }
    }

    /// Reopens the path under `p` for editing: its points become the pen path (document pixels),
    /// its colour and width move into the options; later changes rewrite it live.
    @discardableResult func reopenPath(at p: CGPoint, tolerance: Double) -> Bool {
        guard canEdit, let layer = activeLayer, let stroke = pathStroke(at: p, tolerance: tolerance) else { return false }
        editingPath = nil
        var c = stroke.color; brushOpacity = max(0.05, c.alpha); c.alpha = 1; color = c
        brushSize = stroke.width
        penPath = PenPath(encoded: stroke.points, closed: stroke.pathClosed == true, triples: stroke.pathTriples == true).applying(matrix(layer.transform))
        editingPath = stroke.id
        return true
    }

    /// Colour, opacity and size from the options bar for the reopened path.
    func commitEditedPathStyle() {
        guard let id = editingPath, let layer = activeLayer, let i = layer.strokes.firstIndex(where: { $0.id == id }) else { return }
        var s = layer.strokes[i]
        var c = color; c.alpha *= brushOpacity; s.color = c; s.width = max(1, brushSize)
        guard s != layer.strokes[i] else { return }
        mutateLayer("Edit path") { $0.strokes[i] = s }
    }

    /// Writes the pen path's current shape into the reopened path (fill or stroke stays).
    func syncEditedPath() {
        guard let id = editingPath, let layer = activeLayer, let i = layer.strokes.firstIndex(where: { $0.id == id }) else { return }
        guard let path = penPath, path.nodes.count >= 2 else { return }
        let local = path.applying(matrix(layer.transform).inverted())
        var s = layer.strokes[i]
        s.points = local.encoded; s.pathClosed = path.closed ? true : nil; s.pathTriples = local.hasOwnInHandles ? true : nil
        guard s != layer.strokes[i] else { return }
        mutateLayer("Edit path") { $0.strokes[i] = s }
    }

    /// The path becomes the selection (an open path is closed with a straight line).
    func pathToSelection() {
        guard let path = penPath, path.nodes.count >= 3 else { return }
        var closed = path; closed.closed = true
        selection = CanvasSelection(points: closed.flattened())
    }
}

/// What a pen-tool press grabbed: a new point's handle, an existing anchor, or one of its handles.
enum PenGrab: Equatable, Sendable { case newHandle(Int), anchor(Int), outHandle(Int), inHandle(Int) }

extension Studio {
    /// Existing anchor or handle within `tolerance` of `p` (handles first: they sit on top).
    func penHit(at p: CGPoint, tolerance: Double) -> PenGrab? {
        guard let path = penPath else { return nil }
        func near(_ q: CGPoint) -> Bool { hypot(q.x - p.x, q.y - p.y) <= tolerance }
        for (i, n) in path.nodes.enumerated().reversed() {
            if let o = n.out, near(o) { return .outHandle(i) }
            let h = PenPath.inHandle(n)
            if h != n.anchor, near(h) { return .inHandle(i) }
        }
        for (i, n) in path.nodes.enumerated().reversed() where near(n.anchor) {
            // The first point of an open path closes it instead (see penClick).
            if i == 0, !path.closed, path.nodes.count > 2 { return nil }
            return .anchor(i)
        }
        return nil
    }

    /// A press with the pen tool: grab what is under it, else add a point (or close the path).
    /// Option-pressing an anchor makes it a corner again.
    /// `place` is where a new point goes (snapped to guides), `p` the raw pointer for grabbing.
    /// ⌥ on an anchor makes it a corner, ⌥ on a handle lets the two handles move on their own.
    /// A press on a segment inserts a point there (and grabs it).
    func penPress(at p: CGPoint, place: CGPoint? = nil, tolerance: Double, corner: Bool = false) -> PenGrab? {
        // Without a path in progress, a press on a finished path reopens it.
        let idle: Bool
        if let path = penPath { idle = path.closed && penHit(at: p, tolerance: tolerance) == nil && path.segmentHit(p, tolerance: tolerance) == nil } else { idle = true }
        if idle, reopenPath(at: p, tolerance: tolerance) { return nil }
        if let grab = penHit(at: p, tolerance: tolerance) {
            switch grab {
            case .anchor(let i) where corner: penPath?.nodes[i].out = nil; penPath?.nodes[i].inH = nil; return nil
            case .outHandle(let i) where corner, .inHandle(let i) where corner:
                if let n = penPath?.nodes[i] { penPath?.nodes[i].inH = PenPath.inHandle(n) }
            default: break
            }
            return grab
        }
        if var path = penPath, !path.nodes.contains(where: { hypot($0.anchor.x - p.x, $0.anchor.y - p.y) <= tolerance }),
           let hit = path.segmentHit(p, tolerance: tolerance) {
            let i = path.insert(segment: hit.segment, t: hit.t)
            penPath = path
            return .anchor(i)
        }
        return penClick(at: place ?? p, closeDistance: tolerance).map { .newHandle($0) }
    }

    /// Dragging what `penPress` grabbed: anchors carry their handles, handles stay mirrored.
    func penMove(_ grab: PenGrab, to p: CGPoint) {
        switch grab {
        case .newHandle(let i), .outHandle(let i): penDrag(node: i, to: p)
        case .inHandle(let i):
            guard let n = penPath?.nodes[safe: i] else { return }
            if n.inH != nil { penPath?.nodes[i].inH = p; return }
            penDrag(node: i, to: CGPoint(x: 2 * n.anchor.x - p.x, y: 2 * n.anchor.y - p.y))
        case .anchor(let i):
            guard var path = penPath, path.nodes.indices.contains(i) else { return }
            let d = CGPoint(x: p.x - path.nodes[i].anchor.x, y: p.y - path.nodes[i].anchor.y)
            path.nodes[i].anchor = p
            path.nodes[i].out = path.nodes[i].out.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
            path.nodes[i].inH = path.nodes[i].inH.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
            penPath = path
        }
    }

    /// Backspace with the pen tool: removes the last point (and opens a closed path first).
    func penDeleteLast() {
        guard var path = penPath else { return }
        if path.closed { path.closed = false } else { path.nodes.removeLast() }
        penPath = path.nodes.isEmpty ? nil : path
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
