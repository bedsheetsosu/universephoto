import CoreGraphics

/// Rope stabilizer: the drawn point is dragged behind the Pencil on a string of fixed length,
/// so small jitters inside the string's reach never reach the line.
public struct Rope: Sendable {
    public var length: Double
    public private(set) var point: CGPoint?

    public init(length: Double) { self.length = length }

    public mutating func start(at p: CGPoint) -> CGPoint {
        point = p
        return p
    }

    /// New drawn point for the Pencil at `p`.
    public mutating func pull(to p: CGPoint) -> CGPoint {
        guard let q = point else { return start(at: p) }
        let dx = p.x - q.x, dy = p.y - q.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > length, d > 0 else { return q }
        let k = (d - length) / d
        let n = CGPoint(x: q.x + dx * k, y: q.y + dy * k)
        point = n
        return n
    }

    public mutating func end() { point = nil }
}
