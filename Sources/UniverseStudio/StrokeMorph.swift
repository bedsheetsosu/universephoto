import Foundation

/// Tween with "Morph strokes" (0.90): brush strokes and simple shapes are blended point by point
/// from one frame's drawing to the next – when both frames have the same number of strokes of the
/// same kinds (draw the key poses stroke for stroke). Pixel content can't morph and stays as is.
enum StrokeMorph {
    static let morphableKinds: Set<String?> = [nil, "line", "rectangle", "ellipse", "roundedRect", "arrow"]

    static func canMorph(_ a: [InkStroke], _ b: [InkStroke]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        return zip(a, b).allSatisfy { x, y in
            x.kind == y.kind && morphableKinds.contains(x.kind) && x.isEraser == y.isEraser
                && x.imageData == nil && y.imageData == nil && !x.points.isEmpty && !y.points.isEmpty
        }
    }

    /// `n` points spaced evenly along the polyline (pressure and tilt interpolated too).
    static func resample(_ p: [InkPoint], _ n: Int) -> [InkPoint] {
        guard p.count > 1, n > 1 else { return Array(repeating: p.first ?? InkPoint(x: 0, y: 0, pressure: 1), count: max(1, n)) }
        var cum = [0.0]
        for i in 1..<p.count { cum.append(cum[i - 1] + hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y)) }
        let total = cum.last!
        guard total > 0 else { return Array(repeating: p[0], count: n) }
        var out: [InkPoint] = [], j = 0
        for k in 0..<n {
            let d = total * Double(k) / Double(n - 1)
            while j < p.count - 2 && cum[j + 1] < d { j += 1 }
            let seg = cum[j + 1] - cum[j], t = seg > 0 ? (d - cum[j]) / seg : 0
            out.append(mix(p[j], p[j + 1], t))
        }
        return out
    }

    static func mix(_ a: InkPoint, _ b: InkPoint, _ t: Double) -> InkPoint {
        InkPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, pressure: a.pressure + (b.pressure - a.pressure) * t,
                 tiltX: a.tiltX.map { $0 + ((b.tiltX ?? $0) - $0) * t }, tiltY: a.tiltY.map { $0 + ((b.tiltY ?? $0) - $0) * t },
                 rotation: a.rotation)
    }

    static func mix(_ a: CodableColor, _ b: CodableColor, _ t: Double) -> CodableColor {
        CodableColor(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t, blue: a.blue + (b.blue - a.blue) * t, alpha: a.alpha + (b.alpha - a.alpha) * t)
    }

    /// The in-between drawing at `t`, or nil when the two drawings can't be paired up.
    static func strokes(_ a: [InkStroke], _ b: [InkStroke], _ t: Double) -> [InkStroke]? {
        guard canMorph(a, b) else { return nil }
        return zip(a, b).map { x, y in
            var s = x
            let n = x.points.count == y.points.count ? x.points.count : max(x.points.count, y.points.count, 2)
            let pa = x.points.count == n ? x.points : resample(x.points, n), pb = y.points.count == n ? y.points : resample(y.points, n)
            s.points = zip(pa, pb).map { mix($0, $1, t) }
            s.width = x.width + (y.width - x.width) * t
            s.color = mix(x.color, y.color, t)
            return s
        }
    }
}
