import Foundation
import CoreGraphics

/// Virtual ruler on the iPad (view coordinates). Pencil strokes that start near one of its long
/// edges are kept on that edge's straight line.
public struct Ruler: Equatable, Sendable {
    public var center: CGPoint
    /// Radians, clockwise on screen.
    public var angle: Double
    public var length: Double
    public static let thickness: Double = 84
    /// A stroke snaps when it starts this close to an edge (or anywhere on the ruler).
    public static let snapDistance: Double = 32

    public init(center: CGPoint, angle: Double = 0, length: Double = 3000) {
        self.center = center; self.angle = angle; self.length = length
    }

    var dir: CGPoint { CGPoint(x: cos(angle), y: sin(angle)) }
    var normal: CGPoint { CGPoint(x: -sin(angle), y: cos(angle)) }

    /// Point in ruler space: x along the ruler, y across it (0 = middle line).
    public func local(_ p: CGPoint) -> CGPoint {
        let v = CGPoint(x: p.x - center.x, y: p.y - center.y)
        return CGPoint(x: v.x * dir.x + v.y * dir.y, y: v.x * normal.x + v.y * normal.y)
    }

    public func contains(_ p: CGPoint) -> Bool {
        let q = local(p)
        return abs(q.x) <= length / 2 && abs(q.y) <= Self.thickness / 2
    }

    /// Straight line a stroke starting at `p` should follow, or nil when `p` is too far away.
    /// The line runs just outside the nearer long edge.
    public func snapLine(for p: CGPoint) -> SnapLine? {
        let q = local(p)
        guard abs(q.x) <= length / 2 else { return nil }
        let half = Self.thickness / 2
        guard abs(q.y) <= half + Self.snapDistance else { return nil }
        let side: Double = q.y >= 0 ? 1 : -1
        let off = side * (half + 2)
        return SnapLine(origin: CGPoint(x: center.x + normal.x * off, y: center.y + normal.y * off), direction: dir)
    }

    /// Which long edge a stroke at `p` would follow: -1 top, 1 bottom (ruler space), nil none.
    public func snapSide(for p: CGPoint) -> Int? {
        guard snapLine(for: p) != nil else { return nil }
        return local(p).y >= 0 ? 1 : -1
    }

    /// Angle in whole degrees 0…179 for the label; snaps to multiples of 45° within 2°.
    public static func snapped(_ angle: Double) -> Double {
        let deg = angle * 180 / .pi
        let nearest = (deg / 45).rounded() * 45
        return abs(deg - nearest) < 2 ? nearest * .pi / 180 : angle
    }

    public var degrees: Int {
        var d = Int((angle * 180 / .pi).rounded()) % 180
        if d < 0 { d += 180 }
        return d
    }
}

public struct SnapLine: Equatable, Sendable {
    public var origin: CGPoint
    public var direction: CGPoint
    public init(origin: CGPoint, direction: CGPoint) { self.origin = origin; self.direction = direction }
    /// Closest point on the line.
    public func project(_ p: CGPoint) -> CGPoint {
        let t = (p.x - origin.x) * direction.x + (p.y - origin.y) * direction.y
        return CGPoint(x: origin.x + direction.x * t, y: origin.y + direction.y * t)
    }
}
