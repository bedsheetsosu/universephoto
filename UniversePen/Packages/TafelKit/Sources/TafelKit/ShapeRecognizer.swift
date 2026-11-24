import Foundation
import CoreGraphics

/// A clean shape that replaces a hand-drawn stroke ("hold to snap", like Notes).
public enum RecognizedShape: Equatable, Sendable {
    case line(CGPoint, CGPoint)
    /// Corners in drawing order. Closed polygons connect the last corner back to the first.
    case polygon([CGPoint], closed: Bool)
    /// `angle` in radians: direction of the `rx` axis.
    case ellipse(center: CGPoint, rx: Double, ry: Double, angle: Double)
    /// Straight shaft from `from` to `to` with a symmetric head at `to`.
    case arrow(from: CGPoint, to: CGPoint)

    public var name: String {
        switch self {
        case .line: return "line"
        case .polygon(let c, let closed):
            if !closed { return "polyline" }
            return c.count == 3 ? "triangle" : c.count == 4 ? "quad" : "polygon"
        case .ellipse(_, let rx, let ry, _): return abs(rx - ry) < 0.5 ? "circle" : "ellipse"
        case .arrow: return "arrow"
        }
    }

    /// Points along the outline, at most `spacing` apart, ready to be sent as one stroke.
    public func sampled(spacing: Double) -> [CGPoint] {
        let step = max(spacing, 0.5)
        func segment(_ a: CGPoint, _ b: CGPoint, includeEnd: Bool) -> [CGPoint] {
            let n = max(Int((hypot(b.x - a.x, b.y - a.y) / step).rounded(.up)), 1)
            return (0..<(includeEnd ? n + 1 : n)).map { i in
                let t = Double(i) / Double(n)
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
        }
        switch self {
        case .line(let a, let b):
            return segment(a, b, includeEnd: true)
        case .polygon(let c, let closed):
            guard c.count >= 2 else { return c }
            var out: [CGPoint] = []
            let ends = closed ? c + [c[0]] : c
            for i in 0..<(ends.count - 1) { out += segment(ends[i], ends[i + 1], includeEnd: false) }
            out.append(ends[ends.count - 1])
            return out
        case .arrow(let a, let b):
            let len = hypot(b.x - a.x, b.y - a.y)
            let head = max(min(len * 0.22, 60), 12)
            let back = atan2(a.y - b.y, a.x - b.x)
            let spread = 28 * Double.pi / 180
            let w1 = CGPoint(x: b.x + cos(back + spread) * head, y: b.y + sin(back + spread) * head)
            let w2 = CGPoint(x: b.x + cos(back - spread) * head, y: b.y + sin(back - spread) * head)
            // One stroke: shaft, first barb and back, second barb.
            return segment(a, b, includeEnd: false) + segment(b, w1, includeEnd: false)
                + segment(w1, b, includeEnd: false) + segment(b, w2, includeEnd: true)
        case .ellipse(let o, let rx, let ry, let angle):
            // Ramanujan's perimeter approximation is plenty for spacing.
            let h = pow(rx - ry, 2) / max(pow(rx + ry, 2), 1e-9)
            let perimeter = Double.pi * (rx + ry) * (1 + 3 * h / (10 + sqrt(4 - 3 * h)))
            let n = max(Int(perimeter / step), 24)
            let ca = cos(angle), sa = sin(angle)
            return (0...n).map { i in
                let t = 2 * Double.pi * Double(i) / Double(n)
                let u = rx * cos(t), v = ry * sin(t)
                return CGPoint(x: o.x + u * ca - v * sa, y: o.y + u * sa + v * ca)
            }
        }
    }
}

public enum ShapeRecognizer {
    /// Recognises a line, an open polyline (2–3 bends), a triangle, a quadrilateral (snapped to a
    /// rectangle when its corners are close to right angles), a pentagon, an ellipse or a circle.
    /// `points` in any square-pixel coordinate space. Nil when nothing fits well enough.
    public static func recognize(_ points: [CGPoint]) -> RecognizedShape? {
        let pts = dedupe(points)
        guard pts.count >= 4 else { return nil }
        let length = pathLength(pts)
        let box = bounds(pts)
        let diag = hypot(box.width, box.height)
        guard length > 24, diag > 16 else { return nil }
        let gap = distance(pts[0], pts[pts.count - 1])
        let closed = gap < 0.22 * diag && length > 1.6 * diag

        if !closed {
            let s = simplify(pts, epsilon: max(0.045 * diag, 3))
            if s.count == 2 { return .line(s[0], s[1]) }
            if let arrow = arrow(s) { return arrow }
            if s.count <= 4, meanDistance(pts, toPolyline: s, closed: false) < 0.03 * diag {
                return .polygon(s, closed: false)
            }
            return nil
        }

        // Closed: corners first (a square must not become a circle), then the ellipse.
        var ring = simplify(pts, epsilon: 0.07 * diag)
        if ring.count > 2, distance(ring[0], ring[ring.count - 1]) < 0.22 * diag { ring.removeLast() }
        ring = mergeClose(ring, minDistance: 0.12 * diag)
        if (3...5).contains(ring.count), meanDistance(pts, toPolyline: ring, closed: true) < 0.035 * diag {
            if ring.count == 4, let rect = rectangle(from: ring) { return .polygon(rect, closed: true) }
            return .polygon(ring, closed: true)
        }
        if let e = ellipse(pts), e.error < 0.085 {
            if abs(e.rx - e.ry) / max(e.rx, e.ry) < 0.12 {
                let r = (e.rx + e.ry) / 2
                return .ellipse(center: e.center, rx: r, ry: r, angle: 0)
            }
            return .ellipse(center: e.center, rx: e.rx, ry: e.ry, angle: snapAngle(e.angle))
        }
        return nil
    }

    /// A long shaft followed by a short hook back (one barb, or barb–tip–barb): an arrow.
    static func arrow(_ s: [CGPoint]) -> RecognizedShape? {
        guard s.count == 3 || s.count == 5 else { return nil }
        let start = s[0], tip = s[1]
        let shaft = distance(start, tip)
        guard shaft > 40 else { return nil }
        func isBarb(_ p: CGPoint) -> Bool {
            let d = distance(tip, p)
            guard d < 0.5 * shaft, d > 0.08 * shaft else { return false }
            // The barb points back towards the start: angle to the shaft between 15° and 75°.
            let v1 = CGVector(dx: start.x - tip.x, dy: start.y - tip.y), v2 = CGVector(dx: p.x - tip.x, dy: p.y - tip.y)
            let c = (v1.dx * v2.dx + v1.dy * v2.dy) / (hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy))
            let a = acos(min(max(c, -1), 1)) * 180 / .pi
            return a > 15 && a < 75
        }
        if s.count == 3, isBarb(s[2]) { return .arrow(from: start, to: tip) }
        if s.count == 5, isBarb(s[2]), distance(s[3], tip) < 0.25 * shaft, isBarb(s[4]) { return .arrow(from: start, to: tip) }
        return nil
    }

    // MARK: Helpers

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    static func dedupe(_ p: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for q in p where out.last.map({ distance($0, q) > 0.5 }) ?? true { out.append(q) }
        return out
    }

    static func pathLength(_ p: [CGPoint]) -> Double {
        zip(p, p.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    static func bounds(_ p: [CGPoint]) -> CGRect {
        let xs = p.map(\.x), ys = p.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return distance(p, a) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1)
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    /// Ramer–Douglas–Peucker.
    static func simplify(_ p: [CGPoint], epsilon: Double) -> [CGPoint] {
        guard p.count > 2 else { return p }
        var maxD = 0.0, index = 0
        for i in 1..<(p.count - 1) {
            let d = distance(p[i], toSegment: p[0], p[p.count - 1])
            if d > maxD { maxD = d; index = i }
        }
        guard maxD > epsilon else { return [p[0], p[p.count - 1]] }
        let left = simplify(Array(p[...index]), epsilon: epsilon)
        let right = simplify(Array(p[index...]), epsilon: epsilon)
        return left.dropLast() + right
    }

    static func mergeClose(_ p: [CGPoint], minDistance: Double) -> [CGPoint] {
        var out: [CGPoint] = []
        for q in p where out.last.map({ distance($0, q) >= minDistance }) ?? true { out.append(q) }
        if out.count > 2, distance(out[0], out[out.count - 1]) < minDistance { out.removeLast() }
        return out
    }

    static func meanDistance(_ p: [CGPoint], toPolyline c: [CGPoint], closed: Bool) -> Double {
        let ends = closed ? c + [c[0]] : c
        guard ends.count >= 2 else { return .infinity }
        let total = p.reduce(0.0) { sum, q in
            sum + zip(ends, ends.dropFirst()).map { distance(q, toSegment: $0.0, $0.1) }.min()!
        }
        return total / Double(p.count)
    }

    /// Four corners all within 14° of a right angle → an exact rectangle along the first edge
    /// (snapped to horizontal/vertical when within 6°).
    static func rectangle(from c: [CGPoint]) -> [CGPoint]? {
        for i in 0..<4 {
            let a = c[(i + 3) % 4], b = c[i], d = c[(i + 1) % 4]
            let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y), v2 = CGVector(dx: d.x - b.x, dy: d.y - b.y)
            let cosA = (v1.dx * v2.dx + v1.dy * v2.dy) / max(hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy), 1e-9)
            if abs(acos(min(max(cosA, -1), 1)) - .pi / 2) > 14 * .pi / 180 { return nil }
        }
        let theta = snapAngle(atan2(c[1].y - c[0].y, c[1].x - c[0].x))
        let ux = cos(theta), uy = sin(theta)
        let us = c.map { $0.x * ux + $0.y * uy }, vs = c.map { -$0.x * uy + $0.y * ux }
        let (u0, u1, v0, v1) = (us.min()!, us.max()!, vs.min()!, vs.max()!)
        func pt(_ u: Double, _ v: Double) -> CGPoint { CGPoint(x: u * ux - v * uy, y: u * uy + v * ux) }
        return [pt(u0, v0), pt(u1, v0), pt(u1, v1), pt(u0, v1)]
    }

    /// Angle snapped to a multiple of 90° when within 6°.
    static func snapAngle(_ a: Double) -> Double {
        let quarter = Double.pi / 2
        let nearest = (a / quarter).rounded() * quarter
        return abs(a - nearest) < 6 * .pi / 180 ? nearest : a
    }

    /// Axis-aligned-in-its-own-frame ellipse via principal axes; error = mean relative radial miss.
    static func ellipse(_ p: [CGPoint]) -> (center: CGPoint, rx: Double, ry: Double, angle: Double, error: Double)? {
        let n = Double(p.count)
        let mx = p.reduce(0) { $0 + $1.x } / n, my = p.reduce(0) { $0 + $1.y } / n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for q in p { sxx += (q.x - mx) * (q.x - mx); syy += (q.y - my) * (q.y - my); sxy += (q.x - mx) * (q.y - my) }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let ca = cos(angle), sa = sin(angle)
        let uv = p.map { q -> (Double, Double) in
            let dx = q.x - mx, dy = q.y - my
            return (dx * ca + dy * sa, -dx * sa + dy * ca)
        }
        let u0 = uv.map(\.0).min()!, u1 = uv.map(\.0).max()!, v0 = uv.map(\.1).min()!, v1 = uv.map(\.1).max()!
        let rx = (u1 - u0) / 2, ry = (v1 - v0) / 2
        guard rx > 4, ry > 4 else { return nil }
        let cu = (u0 + u1) / 2, cv = (v0 + v1) / 2
        let center = CGPoint(x: mx + cu * ca - cv * sa, y: my + cu * sa + cv * ca)
        let error = uv.reduce(0.0) { sum, q in
            sum + abs(hypot((q.0 - cu) / rx, (q.1 - cv) / ry) - 1)
        } / n
        return (center, rx, ry, angle, error)
    }
}
