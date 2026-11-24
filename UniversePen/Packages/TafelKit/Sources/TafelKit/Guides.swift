import Foundation
import CoreGraphics

/// Which drawing aid is shown on the iPad (one at a time).
public enum DrawingGuide: Equatable, Sendable {
    case none, ruler
    /// 1–3 vanishing points.
    case perspective(Int)
    case ellipse

    /// Stable short name for storing (per app).
    public var storageName: String {
        switch self {
        case .none: return "none"
        case .ruler: return "ruler"
        case .perspective(let n): return "p\(n)"
        case .ellipse: return "ellipse"
        }
    }

    public init(storageName: String) {
        switch storageName {
        case "ruler": self = .ruler
        case "ellipse": self = .ellipse
        case "p1": self = .perspective(1)
        case "p2": self = .perspective(2)
        case "p3": self = .perspective(3)
        default: self = .none
        }
    }
}

/// Perspective aid: every Pencil stroke follows a line towards one of the vanishing points
/// (or a vertical/horizontal line), chosen by the direction the stroke starts in.
public struct PerspectiveGuide: Equatable, Sendable {
    public var points: [CGPoint]
    /// Movement before the direction is chosen.
    public static let decideDistance: Double = 10
    public static let handleRadius: Double = 30

    public init(points: [CGPoint]) { self.points = points }

    /// Default layout for `count` points in a view of `size`: 1 → centre of a horizon at 40 %,
    /// 2 → both ends of it, 3 → plus one below the middle.
    public static func defaultLayout(count: Int, in size: CGSize) -> PerspectiveGuide {
        let y = size.height * 0.4
        switch count {
        case 1: return PerspectiveGuide(points: [CGPoint(x: size.width / 2, y: y)])
        case 2: return PerspectiveGuide(points: [CGPoint(x: size.width * 0.08, y: y), CGPoint(x: size.width * 0.92, y: y)])
        default:
            return PerspectiveGuide(points: [CGPoint(x: size.width * 0.08, y: y), CGPoint(x: size.width * 0.92, y: y),
                                             CGPoint(x: size.width / 2, y: size.height - 48)])
        }
    }

    /// Directions a stroke at `p` may take: towards each point, plus verticals with fewer than 3
    /// points (the third point replaces them) and horizontals with a single point.
    public func directions(at p: CGPoint) -> [CGPoint] {
        var out: [CGPoint] = []
        for v in points {
            let dx = p.x - v.x, dy = p.y - v.y
            let len = hypot(dx, dy)
            if len > 1 { out.append(CGPoint(x: dx / len, y: dy / len)) }
        }
        if points.count < 3 { out.append(CGPoint(x: 0, y: 1)) }
        if points.count == 1 { out.append(CGPoint(x: 1, y: 0)) }
        return out
    }

    /// The line a stroke from `start` heading to `current` is kept on.
    public func snapLine(start: CGPoint, toward current: CGPoint) -> SnapLine? {
        let mx = current.x - start.x, my = current.y - start.y
        let len = hypot(mx, my)
        guard len > 0 else { return nil }
        let best = directions(at: start).max { a, b in
            abs(a.x * mx + a.y * my) < abs(b.x * mx + b.y * my)
        }
        return best.map { SnapLine(origin: start, direction: $0) }
    }

    /// Index of the vanishing point handle under `p`.
    public func handle(at p: CGPoint) -> Int? {
        points.indices.min { hypot(points[$0].x - p.x, points[$0].y - p.y) < hypot(points[$1].x - p.x, points[$1].y - p.y) }
            .flatMap { hypot(points[$0].x - p.x, points[$0].y - p.y) <= Self.handleRadius ? $0 : nil }
    }
}

/// Ellipse template: strokes that start near its outline follow it.
public struct EllipseGuide: Equatable, Sendable {
    public var center: CGPoint
    public var rx: Double
    public var ry: Double
    /// Radians, clockwise on screen: direction of the rx axis.
    public var angle: Double
    public static let snapDistance: Double = 28
    public static let handleRadius: Double = 28

    public init(center: CGPoint, rx: Double, ry: Double, angle: Double = 0) {
        self.center = center; self.rx = rx; self.ry = ry; self.angle = angle
    }

    public func local(_ p: CGPoint) -> CGPoint {
        let dx = p.x - center.x, dy = p.y - center.y
        return CGPoint(x: dx * cos(angle) + dy * sin(angle), y: -dx * sin(angle) + dy * cos(angle))
    }

    public func world(_ q: CGPoint) -> CGPoint {
        CGPoint(x: center.x + q.x * cos(angle) - q.y * sin(angle), y: center.y + q.x * sin(angle) + q.y * cos(angle))
    }

    /// Nearest point on the outline (radial, in the ellipse's own frame – close enough for drawing).
    public func project(_ p: CGPoint) -> CGPoint {
        let q = local(p)
        let t = atan2(q.y / ry, q.x / rx)
        return world(CGPoint(x: rx * cos(t), y: ry * sin(t)))
    }

    /// Distance from the outline (approximate).
    public func distanceToOutline(_ p: CGPoint) -> Double {
        let o = project(p)
        return hypot(o.x - p.x, o.y - p.y)
    }

    public func snaps(_ p: CGPoint) -> Bool { distanceToOutline(p) <= Self.snapDistance }

    /// Inside, and not on the outline band (fingers there move the template).
    public func containsBody(_ p: CGPoint) -> Bool {
        let q = local(p)
        return pow(q.x / rx, 2) + pow(q.y / ry, 2) < 1 && !snaps(p)
    }

    /// The two axis knobs: 0 = end of the rx axis, 1 = end of the ry axis.
    public var handles: [CGPoint] { [world(CGPoint(x: rx, y: 0)), world(CGPoint(x: 0, y: -ry))] }

    public func handle(at p: CGPoint) -> Int? {
        for (i, h) in handles.enumerated() where hypot(h.x - p.x, h.y - p.y) <= Self.handleRadius { return i }
        return nil
    }

    /// Drags axis knob `i` to `p` (the other axis stays).
    public mutating func drag(handle i: Int, to p: CGPoint) {
        let q = local(p)
        if i == 0 { rx = max(abs(q.x), 20) } else { ry = max(abs(q.y), 20) }
        // Close to round: snap to an exact circle.
        if abs(rx - ry) < 6 { if i == 0 { rx = ry } else { ry = rx } }
    }
}

/// Composition grid over the picture (iPad only).
public enum GridStyle: String, Codable, CaseIterable, Sendable {
    case off, thirds, quarters, squares

    public var title: String {
        switch self {
        case .off: return L("Aus")
        case .thirds: return L("Drittel")
        case .quarters: return L("Viertel")
        case .squares: return L("Quadrate")
        }
    }

    /// Line segments inside `rect`. Squares: `cells` across the longer side.
    public func lines(in rect: CGRect, cells: Int = 8) -> [(CGPoint, CGPoint)] {
        func split(_ n: Int) -> [(CGPoint, CGPoint)] {
            (1..<n).flatMap { i -> [(CGPoint, CGPoint)] in
                let x = rect.minX + rect.width * CGFloat(i) / CGFloat(n)
                let y = rect.minY + rect.height * CGFloat(i) / CGFloat(n)
                return [(CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)),
                        (CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y))]
            }
        }
        switch self {
        case .off: return []
        case .thirds: return split(3)
        case .quarters: return split(4)
        case .squares:
            let cell = max(rect.width, rect.height) / CGFloat(min(max(cells, 2), 64))
            guard cell > 0 else { return [] }
            var out: [(CGPoint, CGPoint)] = []
            var x = rect.minX + cell
            while x < rect.maxX - 0.5 { out.append((CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY))); x += cell }
            var y = rect.minY + cell
            while y < rect.maxY - 0.5 { out.append((CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y))); y += cell }
            return out
        }
    }
}
