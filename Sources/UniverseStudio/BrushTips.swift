import CoreGraphics
import Foundation

/// Brush tips of the pressure brush. `round` is the classic silhouette (stroke field nil).
enum BrushTip: String, CaseIterable, Sendable {
    case round, pencil, marker, airbrush, spray, chalk
    var title: String { switch self { case .round: "Round"; case .pencil: "Pencil"; case .marker: "Marker"; case .airbrush: "Airbrush"; case .spray: "Spray"; case .chalk: "Chalk" } }
    var symbol: String { switch self { case .round: "circle.fill"; case .pencil: "pencil"; case .marker: "highlighter"; case .airbrush: "aqi.medium"; case .spray: "sparkles"; case .chalk: "scribble.variable" } }
}

extension Renderer {
    /// Mouse and tablet events arrive 60–240 times a second, so a fast stroke has samples tens of
    /// pixels apart. A centripetal Catmull-Rom curve through them (no overshoot, no loops) with
    /// extra points every few pixels makes the outline round instead of a polygon. Pressure, tilt
    /// and roll are interpolated along; the real samples stay in the stroke.
    static func smoothed(_ pts: [InkPoint], width: Double) -> [InkPoint] {
        guard pts.count >= 3 else { return pts }
        let step = max(1.5, min(6, width * 0.2))
        func lerp(_ a: Double?, _ b: Double?, _ t: Double) -> Double? { guard let a, let b else { return a ?? b }; return a + (b - a) * t }
        var out: [InkPoint] = [pts[0]]
        out.reserveCapacity(pts.count * 2)
        for i in 0..<(pts.count - 1) {
            let p1 = pts[i], p2 = pts[i + 1]
            let len = hypot(p2.x - p1.x, p2.y - p1.y)
            let n = Int(len / step)
            if n >= 2 {
                let p0 = i > 0 ? pts[i - 1] : p1, p3 = i + 2 < pts.count ? pts[i + 2] : p2
                // Centripetal parameterisation (alpha 0.5).
                func knot(_ a: InkPoint, _ b: InkPoint) -> Double { max(1e-4, pow(hypot(b.x - a.x, b.y - a.y), 0.5)) }
                let t0 = 0.0, t1 = t0 + knot(p0, p1), t2 = t1 + knot(p1, p2), t3 = t2 + knot(p2, p3)
                func coord(_ v0: Double, _ v1: Double, _ v2: Double, _ v3: Double, _ t: Double) -> Double {
                    let a1 = (t1 - t) / (t1 - t0) * v0 + (t - t0) / (t1 - t0) * v1
                    let a2 = (t2 - t) / (t2 - t1) * v1 + (t - t1) / (t2 - t1) * v2
                    let a3 = (t3 - t) / (t3 - t2) * v2 + (t - t2) / (t3 - t2) * v3
                    let b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
                    let b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
                    return (t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2
                }
                for k in 1..<n {
                    let f = Double(k) / Double(n), t = t1 + (t2 - t1) * f
                    let x = coord(p0.x, p1.x, p2.x, p3.x, t), y = coord(p0.y, p1.y, p2.y, p3.y, t)
                    guard x.isFinite, y.isFinite else { continue }
                    out.append(InkPoint(x: x, y: y, pressure: p1.pressure + (p2.pressure - p1.pressure) * f,
                                        tiltX: lerp(p1.tiltX, p2.tiltX, f), tiltY: lerp(p1.tiltY, p2.tiltY, f), rotation: lerp(p1.rotation, p2.rotation, f)))
                }
            }
            out.append(p2)
        }
        return out
    }

    /// SplitMix64 seeded from the stroke id: the same stroke always sprays the same dots.
    struct StrokeRandom {
        private var state: UInt64
        init(_ id: UUID) { let u = id.uuid; state = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7].reduce(0) { $0 << 8 | UInt64($1) } ^ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
    }

    /// Points every `spacing` px along the stroke, with interpolated pressure.
    static func dabs(_ stroke: InkStroke, spacing: (Double) -> Double) -> [(CGPoint, Double)] {
        let pts = smoothed(stroke.points.filter { $0.x.isFinite && $0.y.isFinite }, width: stroke.width)
        guard let first = pts.first else { return [] }
        func pr(_ p: InkPoint) -> Double { max(0.05, min(1, p.pressure.isFinite ? p.pressure : 1)) }
        var out = [(CGPoint(x: first.x, y: first.y), pr(first))]
        var remaining = spacing(stroke.width * pr(first) / 2)   // distance to the next dab
        for (a, b) in zip(pts, pts.dropFirst()) {
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 0.0001 else { continue }
            var pos = 0.0
            while remaining <= len - pos {
                pos += remaining
                let t = pos / len, p = pr(a) + (pr(b) - pr(a)) * t
                out.append((CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), p))
                remaining = spacing(stroke.width * p / 2)
                if out.count > 200_000 { return out }
            }
            remaining -= len - pos
        }
        return out
    }

    /// Draws a pressure brush stroke with its tip (the colour and blend are already set).
    /// Grey matte (white = full ink, row 0 = top) of a stroke's pressure along its path.
    static func pressureMatte(_ stroke: InkStroke, width w: Int, height h: Int) -> CGImage? {
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)   // draw y-down like the layer
        ctx.setBlendMode(.lighten); ctx.setLineCap(.round); ctx.setLineWidth(max(1, stroke.width) + 2)
        let pts = stroke.points.filter { $0.x.isFinite && $0.y.isFinite }
        func level(_ p: InkPoint) -> Double { max(0.04, min(1, p.pressure.isFinite ? p.pressure : 1)) }
        if pts.count == 1, let p = pts.first {
            ctx.setFillColor(gray: level(p), alpha: 1)
            ctx.fillEllipse(in: CGRect(x: p.x - stroke.width / 2 - 1, y: p.y - stroke.width / 2 - 1, width: stroke.width + 2, height: stroke.width + 2))
        }
        for (a, b) in zip(pts, pts.dropFirst()) {
            ctx.setStrokeColor(gray: (level(a) + level(b)) / 2, alpha: 1)
            ctx.move(to: CGPoint(x: a.x, y: a.y)); ctx.addLine(to: CGPoint(x: b.x, y: b.y)); ctx.strokePath()
        }
        return ctx.makeImage()
    }

    static func drawTip(_ tip: BrushTip, _ stroke: InkStroke, in context: CGContext) {
        let color = stroke.color
        switch tip {
        case .round where stroke.hasDynamics:
            drawDynamicDabs(stroke, in: context)
        case .round:
            if stroke.pressureOpacity == true, let matte = pressureMatte(stroke, width: context.width, height: context.height) {
                // Ink only as dense as the pen pressed: the silhouette filled through a grey matte
                // (per pixel the strongest pressure that touched it, so overlaps don't build up).
                let h = CGFloat(context.height)
                context.saveGState()
                context.translateBy(x: 0, y: h); context.scaleBy(x: 1, y: -1)
                context.clip(to: CGRect(x: 0, y: 0, width: matte.width, height: matte.height), mask: matte)
                context.scaleBy(x: 1, y: -1); context.translateBy(x: 0, y: -h)
                context.addPath(brushPath(stroke)); context.fillPath()
                context.restoreGState()
            } else {
                context.addPath(brushPath(stroke)); context.fillPath()
            }
        case .pencil:
            context.setShouldAntialias(false)
            context.addPath(brushPath(stroke)); context.fillPath()
        case .marker:
            // Flat width, translucent ink that never darkens where the stroke crosses itself.
            var flat = stroke; flat.points = stroke.points.map { var p = $0; p.pressure = 1; p.tiltX = nil; p.tiltY = nil; return p }
            context.setAlpha(0.55)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setFillColor(color.cgColor)
            context.addPath(brushPath(flat)); context.fillPath()
            context.endTransparencyLayer()
        case .airbrush:
            // Soft dabs that build up; pressure sets both size and flow.
            let space = CGColorSpace(name: CGColorSpace.sRGB)
            for (c, p) in dabs(stroke, spacing: { max(0.5, $0 * 0.3) }) {
                let r = max(0.5, stroke.width * p / 2) * 1.6
                var inner = color; inner.alpha *= 0.14 * p
                var outer = color; outer.alpha = 0
                guard let g = CGGradient(colorsSpace: space, colors: [inner.cgColor, outer.cgColor] as CFArray, locations: [0, 1]) else { continue }
                context.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            }
        case .spray, .chalk:
            var rng = StrokeRandom(stroke.id)
            let chalk = tip == .chalk
            if chalk {   // a faint body under the grain
                context.saveGState(); context.setAlpha(0.3)
                context.addPath(brushPath(stroke)); context.fillPath()
                context.restoreGState()
            }
            let dots = CGMutablePath()
            for (c, p) in dabs(stroke, spacing: { max(1, $0 * (chalk ? 0.25 : 0.5)) }) {
                let r = max(1, stroke.width * p / 2) * (chalk ? 1 : 1.5)
                let count = Int(max(2, (chalk ? 0.9 : 0.35) * r * p))
                for _ in 0..<count {
                    // Spray: denser in the middle; chalk: even grain across the tip.
                    let d = chalk ? r * rng.next().squareRoot() : r * rng.next() * rng.next().squareRoot()
                    let a = rng.next() * 2 * .pi
                    let s = chalk ? 0.5 + rng.next() * 1.2 : 0.4 + rng.next() * (0.6 + stroke.width * 0.012)
                    dots.addEllipse(in: CGRect(x: c.x + cos(a) * d - s, y: c.y + sin(a) * d - s, width: s * 2, height: s * 2))
                }
            }
            context.addPath(dots); context.fillPath()
        }
    }

    /// Round brush with dynamics: round dabs along the path, each thrown off by up to `scatter` ×
    /// the brush size, sized by `sizeJitter` and tinted by `hueJitter`. Seeded by the stroke, so
    /// the same stroke always looks the same (also after saving and reopening).
    static func drawDynamicDabs(_ stroke: InkStroke, in context: CGContext) {
        var rng = StrokeRandom(stroke.id)
        let scatter = max(0, min(1, stroke.scatter ?? 0)), sizeJ = max(0, min(1, stroke.sizeJitter ?? 0)), hueJ = max(0, min(1, stroke.hueJitter ?? 0))
        // Scattered dabs stand apart; without scatter they overlap into a line.
        let spacingFactor = scatter > 0 ? 0.6 + scatter : 0.25
        let base = stroke.color
        for (c, p) in dabs(stroke, spacing: { max(0.75, $0 * spacingFactor) }) {
            var r = max(0.5, stroke.width * p / 2)
            if sizeJ > 0 { r *= 1 - sizeJ * rng.next() }
            var at = c
            if scatter > 0 {
                let a = rng.next() * 2 * .pi, d = stroke.width * scatter * rng.next().squareRoot()
                at = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            }
            var color = base
            if hueJ > 0 { color = base.hueShifted(by: (rng.next() * 2 - 1) * hueJ / 6) }
            if stroke.pressureOpacity == true { color.alpha *= p }
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
        }
    }
}

extension CodableColor {
    /// The same colour with its hue turned by `turns` (1 = full circle).
    func hueShifted(by turns: Double) -> CodableColor {
        let mx = max(red, green, blue), mn = min(red, green, blue), d = mx - mn
        guard d > 0.0001 else { return self }
        var h: Double
        if mx == red { h = (green - blue) / d } else if mx == green { h = (blue - red) / d + 2 } else { h = (red - green) / d + 4 }
        h = (h / 6 + turns).truncatingRemainder(dividingBy: 1); if h < 0 { h += 1 }
        let sat = d / mx, v = mx
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - sat), q = v * (1 - f * sat), t = v * (1 - (1 - f) * sat)
        let (r, g, b): (Double, Double, Double) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
        return CodableColor(red: r, green: g, blue: b, alpha: alpha)
    }
}
