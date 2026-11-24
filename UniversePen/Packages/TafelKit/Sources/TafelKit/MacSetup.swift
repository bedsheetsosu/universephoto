import Foundation

/// The Pencil part of the settings that belongs to one Mac (1.3): set up once after pairing it and
/// switched in automatically whenever that Mac connects.
public struct MacPenSetup: Codable, Equatable, Sendable {
    public var pen: PenProfile
    public var tipThreshold: Double
    public var sendHover: Bool
    public var hoverDot: Bool
    public var hoverTilt: Bool

    public init(_ s: InputSettings) {
        pen = s.penProfile; tipThreshold = s.tipThreshold
        sendHover = s.sendHover; hoverDot = s.hoverDot; hoverTilt = s.hoverTilt
    }

    public func apply(to s: inout InputSettings) {
        s.penProfile = pen; s.tipThreshold = tipThreshold
        s.sendHover = sendHover; s.hoverDot = hoverDot; s.hoverTilt = hoverTilt
    }
}

/// Turns two practice strokes (one light, one firm) into a pressure curve: your light touch gives
/// about a quarter, your firm one nearly full output, so the whole range is easy to reach.
public enum PressureCalibration {
    /// `q`-quantile (0…1) of the samples, nil without samples.
    public static func quantile(_ v: [Double], _ q: Double) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted(), i = min(s.count - 1, max(0, Int((Double(s.count - 1) * q).rounded())))
        return s[i]
    }

    /// Curve from normalised forces (0…1) of a light and a firm stroke; nil when they are unusable.
    public static func curve(light: [Double], firm: [Double], minimum: Double = 0.01) -> PressureCurve? {
        guard light.count >= 5, firm.count >= 5, var l = quantile(light, 0.5), var f = quantile(firm, 0.9) else { return nil }
        l = min(max(l, 0.03), 0.6)
        f = min(max(f, l + 0.15), 1)
        let mid = (l + f) / 2
        var pts = [CurvePoint(0, 0), CurvePoint(l, 0.25), CurvePoint(mid, 0.62)]
        if f < 0.98 { pts += [CurvePoint(f, 0.97), CurvePoint(1, 1)] } else { pts.append(CurvePoint(1, 1)) }
        return PressureCurve(gamma: 1, minimum: minimum, points: pts)
    }

    /// Click threshold from the (curved) peak pressure of a few deliberate clicks: a bit below
    /// your usual click, so light touches stay hovering.
    public static func clickThreshold(peaks: [Double]) -> Double? {
        guard let m = quantile(peaks, 0.5) else { return nil }
        return min(0.6, max(0.05, (m * 0.6 * 100).rounded() / 100))
    }
}
