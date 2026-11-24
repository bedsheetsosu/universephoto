import CoreGraphics
import Foundation

/// Animation → Follow path (0.100): draw a route with the pen tool (or use the last pen path in
/// the frame), and the active layer travels along it over new frames – evenly spaced or easing
/// in and out, optionally turning with the path's direction.
enum FollowPath {
    /// The path as a polyline (curves split into short pieces).
    static func polyline(_ path: CGPath, segments: Int = 24) -> [CGPoint] {
        var out: [CGPoint] = [], cur = CGPoint.zero, start = CGPoint.zero
        path.applyWithBlock { e in
            let p = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: cur = p[0]; start = cur; out.append(cur)
            case .addLineToPoint: cur = p[0]; out.append(cur)
            case .addQuadCurveToPoint:
                let a = cur
                for k in 1...segments { let t = CGFloat(k) / CGFloat(segments), u = 1 - t
                    out.append(CGPoint(x: u * u * a.x + 2 * u * t * p[0].x + t * t * p[1].x, y: u * u * a.y + 2 * u * t * p[0].y + t * t * p[1].y)) }
                cur = p[1]
            case .addCurveToPoint:
                let a = cur
                for k in 1...segments { let t = CGFloat(k) / CGFloat(segments), u = 1 - t
                    let x = u * u * u * a.x + 3 * u * u * t * p[0].x + 3 * u * t * t * p[1].x + t * t * t * p[2].x
                    let y = u * u * u * a.y + 3 * u * u * t * p[0].y + 3 * u * t * t * p[1].y + t * t * t * p[2].y
                    out.append(CGPoint(x: x, y: y)) }
                cur = p[2]
            case .closeSubpath: cur = start; out.append(start)
            @unknown default: break
            }
        }
        return out
    }

    /// Point and direction (degrees) at `t` (0…1) of the polyline's length.
    static func sample(_ pts: [CGPoint], at t: Double) -> (CGPoint, Double)? {
        guard pts.count > 1 else { return pts.first.map { ($0, 0) } }
        var lengths = [0.0]
        for i in 1..<pts.count { lengths.append(lengths[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        let total = lengths.last!
        guard total > 0 else { return (pts[0], 0) }
        let d = min(max(t, 0), 1) * total
        var i = 1
        while i < pts.count - 1 && lengths[i] < d { i += 1 }
        let seg = lengths[i] - lengths[i - 1], u = seg > 0 ? (d - lengths[i - 1]) / seg : 0
        let a = pts[i - 1], b = pts[i]
        return (CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u), atan2(b.y - a.y, b.x - a.x) * 180 / .pi)
    }
}

extension Studio {
    /// The route: the pen path being drawn, else the newest pen path in this frame.
    func routePath() -> CGPath? {
        if let p = penPath, p.nodes.count > 1 { return p.cgPath }
        for layer in layers.reversed() {
            if let s = layer.strokes.last(where: { $0.kind == "path" && $0.points.count > 2 }) {
                let path = PenPath(encoded: s.points, closed: s.pathClosed == true, triples: s.pathTriples == true).cgPath
                var m = matrix(layer.transform)
                return path.copy(using: &m) ?? path
            }
        }
        return nil
    }

    /// Replaces the current frame with `count` frames moving the active layer along the route.
    @discardableResult func followPath(count: Int, eased: Bool, orient: Bool) -> Int {
        guard count > 1, let route = routePath(), let layer = activeLayer, !layer.isAdjustmentLayer,
              let box = contentBounds(layer) else { return 0 }
        let pts = FollowPath.polyline(route)
        guard pts.count > 1 else { return 0 }
        stopPlayback(); checkpoint("Follow path")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let source = frames[frameIndex], id = layer.id
        let centre = CGPoint(x: box.midX, y: box.midY).applying(matrix(layer.transform))
        let startAngle = FollowPath.sample(pts, at: 0)?.1 ?? 0
        let made: [[ArtLayer]] = (0..<count).map { k in
            let t = Tween.ease(Double(k) / Double(count - 1), eased: eased)
            guard let (p, angle) = FollowPath.sample(pts, at: t) else { return source }
            return source.map { l in
                guard l.id == id else { return l }
                var m = l
                m.transform.x += p.x - centre.x; m.transform.y += p.y - centre.y
                if orient { m.transform.rotation += angle - startAngle }
                return m
            }
        }
        frames[frameIndex] = made[0]
        metaInsert(at: frameIndex + 1, holds: Array(repeating: 1, count: count - 1))
        frames.insert(contentsOf: made.dropFirst(), at: frameIndex + 1)
        layers = frames[frameIndex]
        changed()
        return count
    }
}
