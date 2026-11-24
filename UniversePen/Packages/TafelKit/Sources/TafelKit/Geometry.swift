import Foundation
import CoreGraphics

public enum Geometry {
    /// Rectangle of `content` scaled to fit inside `container`, centered (aspect fit).
    public static func aspectFit(content: CGSize, in container: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return container }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Largest rect with the given aspect ratio (w/h) inside `bounds`, scaled by `zoom` (0...1],
    /// positioned by `anchor` (0...1 per axis, 0.5 = centered).
    public static func region(aspect: Double, in bounds: CGRect, zoom: Double = 1, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGRect {
        guard aspect > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let z = min(max(zoom, 0.1), 1)
        var w = bounds.width
        var h = w / aspect
        if h > bounds.height {
            h = bounds.height
            w = h * aspect
        }
        w *= z; h *= z
        let ax = min(max(anchor.x, 0), 1), ay = min(max(anchor.y, 0), 1)
        return CGRect(x: bounds.minX + (bounds.width - w) * ax,
                      y: bounds.minY + (bounds.height - h) * ay,
                      width: w, height: h)
    }

    /// Normalized (0...1) position of `point` inside `rect`, clamped. Origin top-left.
    public static func normalized(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(x: min(max((point.x - rect.minX) / rect.width, 0), 1),
                       y: min(max((point.y - rect.minY) / rect.height, 0), 1))
    }

    /// Maps a normalized point back to a point in `region` (e.g. global Mac display coordinates).
    public static func denormalized(_ p: CGPoint, in region: CGRect) -> CGPoint {
        CGPoint(x: region.minX + p.x * region.width, y: region.minY + p.y * region.height)
    }

    /// Output stream size: source aspect fitted into the target pixel size times `scale`,
    /// rounded down to even numbers (required by 4:2:0 encoders).
    public static func streamSize(sourceAspect: Double, targetWidth: Int, targetHeight: Int, scale: Double) -> (width: Int, height: Int) {
        let s = min(max(scale, 0.25), 1)
        let tw = Double(targetWidth) * s, th = Double(targetHeight) * s
        guard sourceAspect > 0, tw > 0, th > 0 else { return (2, 2) }
        var w = tw, h = tw / sourceAspect
        if h > th { h = th; w = th * sourceAspect }
        func even(_ v: Double) -> Int { max(2, Int(v) & ~1) }
        return (even(w), even(h))
    }
}

/// Converts Äbbl Pencil angles to Wacom-style tilt values (-1...1 per axis).
///
/// altitude: 0 = flat on the glass, π/2 = perpendicular. azimuth: direction in the view's
/// coordinate space, 0 = +x (right), positive towards +y (down). The *sign convention* that
/// drawing apps on macOS expect has not been verified against real hardware yet, so both axes
/// can be inverted in the settings.
public struct TiltConverter: Codable, Equatable, Sendable {
    public var invertX: Bool
    public var invertY: Bool

    public init(invertX: Bool = false, invertY: Bool = false) {
        self.invertX = invertX
        self.invertY = invertY
    }

    public func tilt(altitude: Double, azimuth: Double) -> (x: Double, y: Double) {
        let magnitude = cos(min(max(altitude, 0), .pi / 2))
        var x = magnitude * cos(azimuth)
        var y = magnitude * sin(azimuth)
        if invertX { x = -x }
        if invertY { y = -y }
        return (min(max(x, -1), 1), min(max(y, -1), 1))
    }
}

/// Simple gamma pressure curve with a minimum output while touching, so very light strokes
/// still register in apps that treat pressure 0 as "no stroke".
public struct CurvePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

/// Maps Pencil force (0…1) to the pressure sent to the Mac.
/// Either a simple gamma, or – when `points` is set – a freely drawn curve through control points
/// (monotone cubic interpolation, so it never overshoots or runs backwards).
public struct PressureCurve: Codable, Equatable, Sendable {
    /// < 1 = softer (more output for light pressure), > 1 = harder. Used when `points` is empty.
    public var gamma: Double
    public var minimum: Double
    /// Control points sorted by x, first at x = 0 and last at x = 1. Empty = use `gamma`.
    public var points: [CurvePoint]

    public init(gamma: Double = 1.0, minimum: Double = 0.01, points: [CurvePoint] = []) {
        self.gamma = gamma
        self.minimum = minimum
        self.points = points
    }

    private enum CodingKeys: String, CodingKey { case gamma, minimum, points }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gamma = try c.decodeIfPresent(Double.self, forKey: .gamma) ?? 1
        minimum = try c.decodeIfPresent(Double.self, forKey: .minimum) ?? 0.01
        points = try c.decodeIfPresent([CurvePoint].self, forKey: .points) ?? []
    }

    /// Ready-made curves for the editor (the minimum stays as it is).
    public enum Preset: String, CaseIterable, Sendable {
        case soft, linear, firm, sCurve

        public var title: String {
            switch self {
            case .soft: return L("Weich")
            case .linear: return L("Linear")
            case .firm: return L("Fest")
            case .sCurve: return L("S-Kurve")
            }
        }

        public var points: [CurvePoint] {
            switch self {
            case .soft: return [CurvePoint(0, 0), CurvePoint(0.25, 0.45), CurvePoint(0.5, 0.7), CurvePoint(0.75, 0.88), CurvePoint(1, 1)]
            case .linear: return [CurvePoint(0, 0), CurvePoint(0.25, 0.25), CurvePoint(0.5, 0.5), CurvePoint(0.75, 0.75), CurvePoint(1, 1)]
            case .firm: return [CurvePoint(0, 0), CurvePoint(0.25, 0.08), CurvePoint(0.5, 0.25), CurvePoint(0.75, 0.55), CurvePoint(1, 1)]
            case .sCurve: return [CurvePoint(0, 0), CurvePoint(0.25, 0.12), CurvePoint(0.5, 0.5), CurvePoint(0.75, 0.88), CurvePoint(1, 1)]
            }
        }
    }

    public mutating func apply(_ preset: Preset) { points = preset.points }

    /// Five editable points that reproduce the current gamma curve (start of the editor).
    public func editablePoints() -> [CurvePoint] {
        if points.count >= 2 { return points }
        return [0, 0.25, 0.5, 0.75, 1].map { CurvePoint($0, map($0)) }
    }

    /// The curve itself, without the minimum.
    public func map(_ n: Double) -> Double {
        let x = min(max(n, 0), 1)
        guard points.count >= 2 else { return pow(x, min(max(gamma, 0.2), 5)) }
        return Self.monotoneCubic(points, at: x)
    }

    public func apply(force: Double, maximumForce: Double) -> Double {
        guard maximumForce > 0 else { return 1 }
        return max(map(force / maximumForce), minimum)
    }

    /// Fritsch–Carlson monotone cubic Hermite interpolation.
    static func monotoneCubic(_ pts: [CurvePoint], at x: Double) -> Double {
        let p = pts.sorted { $0.x < $1.x }
        let n = p.count
        if x <= p[0].x { return min(max(p[0].y, 0), 1) }
        if x >= p[n - 1].x { return min(max(p[n - 1].y, 0), 1) }
        var d = [Double](repeating: 0, count: n - 1)
        for k in 0..<(n - 1) {
            let dx = p[k + 1].x - p[k].x
            d[k] = dx > 0 ? (p[k + 1].y - p[k].y) / dx : 0
        }
        var m = [Double](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        for k in 1..<(n - 1) { m[k] = d[k - 1] * d[k] <= 0 ? 0 : (d[k - 1] + d[k]) / 2 }
        for k in 0..<(n - 1) where d[k] == 0 {
            m[k] = 0; m[k + 1] = 0
        }
        for k in 0..<(n - 1) where d[k] != 0 {
            let a = m[k] / d[k], b = m[k + 1] / d[k]
            let s = a * a + b * b
            if s > 9 { let t = 3 / s.squareRoot(); m[k] = t * a * d[k]; m[k + 1] = t * b * d[k] }
        }
        var k = 0
        while k < n - 2 && x > p[k + 1].x { k += 1 }
        let h = p[k + 1].x - p[k].x
        guard h > 0 else { return p[k].y }
        let t = (x - p[k].x) / h
        let t2 = t * t, t3 = t2 * t
        let y = (2 * t3 - 3 * t2 + 1) * p[k].y + (t3 - 2 * t2 + t) * h * m[k]
            + (-2 * t3 + 3 * t2) * p[k + 1].y + (t3 - t2) * h * m[k + 1]
        return min(max(y, 0), 1)
    }
}

/// Exponential smoothing for Pencil samples (0 = off, 1 = very smooth / more lag).
public struct SampleSmoother: Sendable {
    public var amount: Double
    private var last: Double?
    public init(amount: Double) { self.amount = amount }
    public mutating func reset() { last = nil }
    public mutating func add(_ v: Double) -> Double {
        guard amount > 0, let l = last else { last = v; return v }
        let alpha = 1 - 0.85 * min(max(amount, 0), 1)
        let r = l + alpha * (v - l)
        last = r
        return r
    }
}

/// Integer remainder accumulator for scroll deltas.
public struct DeltaAccumulator: Sendable {
    private var rest: Double = 0
    public init() {}
    public mutating func take(_ delta: Double) -> Int {
        rest += delta
        let whole = rest.rounded(.towardZero)
        rest -= whole
        return Int(whole)
    }
}

/// Converts a continuous value (pinch log-scale, rotation angle) into discrete steps.
public struct StepAccumulator: Sendable {
    public var stepSize: Double
    private var acc: Double = 0
    public init(stepSize: Double) { self.stepSize = stepSize }
    public mutating func reset() { acc = 0 }
    /// Returns signed number of whole steps crossed by adding `delta`.
    public mutating func add(_ delta: Double) -> Int {
        guard stepSize > 0 else { return 0 }
        acc += delta
        let steps = Int((acc / stepSize).rounded(.towardZero))
        acc -= Double(steps) * stepSize
        return steps
    }
}
