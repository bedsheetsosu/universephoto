import SwiftUI
import CoreGraphics

struct CurvePoint: Codable, Equatable, Sendable { var x: Double; var y: Double }

/// Tone curves: monotone cubic interpolation (no overshoot between points, like Photoshop's
/// curves), applied per channel first and then the RGB master curve.
enum ToneCurve {
    static let channels = ["rgb", "red", "green", "blue"]
    static let identity = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    static func isIdentity(_ points: [CurvePoint]) -> Bool { points.allSatisfy { abs($0.x - $0.y) < 0.0005 } }

    /// Value of the curve at x (0…1).
    static func evaluate(_ points: [CurvePoint], at x: Double) -> Double {
        let p = points.sorted { $0.x < $1.x }
        guard p.count >= 2 else { return x }
        if x <= p[0].x { return clamp(p[0].y) }
        if x >= p[p.count - 1].x { return clamp(p[p.count - 1].y) }
        let n = p.count
        var d = [Double](repeating: 0, count: n - 1)       // secant slopes
        for i in 0..<(n - 1) { d[i] = (p[i + 1].y - p[i].y) / max(1e-6, p[i + 1].x - p[i].x) }
        var m = [Double](repeating: 0, count: n)            // tangents (Fritsch–Carlson)
        m[0] = d[0]; m[n - 1] = d[n - 2]
        for i in 1..<(n - 1) { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
        for i in 0..<(n - 1) where d[i] == 0 { m[i] = 0; m[i + 1] = 0 }
        for i in 0..<(n - 1) where d[i] != 0 {
            let a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b
            if s > 9 { let t = 3 / s.squareRoot(); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i] }
        }
        var k = 0
        while k < n - 2 && x > p[k + 1].x { k += 1 }
        let h = p[k + 1].x - p[k].x, t = (x - p[k].x) / max(1e-6, h)
        let t2 = t * t, t3 = t2 * t
        let y = (2 * t3 - 3 * t2 + 1) * p[k].y + (t3 - 2 * t2 + t) * h * m[k] + (-2 * t3 + 3 * t2) * p[k + 1].y + (t3 - t2) * h * m[k + 1]
        return clamp(y)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    /// 256 RGB float triplets for CIColorCurves; nil when every curve is straight.
    static func table(_ curves: [String: [CurvePoint]]) -> Data? {
        guard curves.values.contains(where: { !isIdentity($0) }) else { return nil }
        let master = curves["rgb"] ?? identity
        var floats = [Float]()
        floats.reserveCapacity(256 * 3)
        for i in 0..<256 {
            let x = Double(i) / 255
            for ch in ["red", "green", "blue"] {
                floats.append(Float(evaluate(master, at: evaluate(curves[ch] ?? identity, at: x))))
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Luminance histogram (256 bins) of a picture, from a small copy; transparent pixels skipped.
    static func histogram(_ image: CGImage) -> [Double] {
        let w = min(256, image.width), h = max(1, Int(Double(image.height) * Double(w) / Double(max(1, image.width))))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.assumingMemoryBound(to: UInt8.self)
        var bins = [Double](repeating: 0, count: 256)
        for i in 0..<(w * h) {
            let a = Double(px[i * 4 + 3]); guard a > 8 else { continue }
            let l = (0.2126 * Double(px[i * 4]) + 0.7152 * Double(px[i * 4 + 1]) + 0.0722 * Double(px[i * 4 + 2])) * 255 / a
            bins[min(255, max(0, Int(l)))] += 1
        }
        let peak = bins.max() ?? 0
        return peak > 0 ? bins.map { ($0 / peak).squareRoot() } : bins
    }
}

/// Curves editor: drag points, click to add, drag a middle point out of the box to remove it.
struct CurvesEditor: View {
    @Environment(\.photoTheme) private var theme
    var curves: [String: [CurvePoint]]
    var histogram: [Double]
    var set: ([String: [CurvePoint]]?) -> Void
    /// Channels offered; one channel hides the picker (e.g. the pressure curve).
    var channels: [String] = ToneCurve.channels
    @State private var channel = "rgb"
    @State private var dragging: Int?

    private var points: [CurvePoint] { (curves[channel] ?? ToneCurve.identity).sorted { $0.x < $1.x } }
    private var color: Color { switch channel { case "red": .red; case "green": .green; case "blue": .blue; default: theme.accent } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(channels.count > 1 ? channels : [], id: \.self) { ch in
                    Button { channel = ch } label: {
                        Text(ch == "rgb" ? "RGB" : L(ch.capitalized)).font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(channel == ch ? theme.onAccent : theme.text)
                            .background(channel == ch ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.card), in: Capsule())
                    }.buttonStyle(PhotoPress()).accessibilityAddTraits(channel == ch ? .isSelected : [])
                }
                Spacer()
                Button { var c = curves; c[channel] = nil; set(c.values.allSatisfy(ToneCurve.isIdentity) ? nil : c) } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(PhotoPress()).help(L("Reset curve")).accessibilityLabel(L("Reset curve"))
            }
            GeometryReader { g in
                let size = g.size
                Canvas { ctx, sz in
                    let r = CGRect(origin: .zero, size: sz)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(theme.deep.opacity(0.6)))
                    if !histogram.isEmpty {   // histogram behind the curve
                        var hist = Path(); hist.move(to: CGPoint(x: 0, y: sz.height))
                        for (i, v) in histogram.enumerated() { hist.addLine(to: CGPoint(x: Double(i) / 255 * sz.width, y: sz.height * (1 - v * 0.9))) }
                        hist.addLine(to: CGPoint(x: sz.width, y: sz.height)); hist.closeSubpath()
                        ctx.fill(hist, with: .color(theme.text.opacity(0.12)))
                    }
                    var grid = Path()
                    for i in 1..<4 { let f = Double(i) / 4; grid.move(to: CGPoint(x: f * sz.width, y: 0)); grid.addLine(to: CGPoint(x: f * sz.width, y: sz.height)); grid.move(to: CGPoint(x: 0, y: f * sz.height)); grid.addLine(to: CGPoint(x: sz.width, y: f * sz.height)) }
                    ctx.stroke(grid, with: .color(theme.outline), lineWidth: 0.5)
                    var diag = Path(); diag.move(to: CGPoint(x: 0, y: sz.height)); diag.addLine(to: CGPoint(x: sz.width, y: 0))
                    ctx.stroke(diag, with: .color(theme.text.opacity(0.15)), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                    var curve = Path()
                    for i in 0...96 { let x = Double(i) / 96; let p = CGPoint(x: x * sz.width, y: (1 - ToneCurve.evaluate(points, at: x)) * sz.height); i == 0 ? curve.move(to: p) : curve.addLine(to: p) }
                    ctx.stroke(curve, with: .color(color), lineWidth: 1.6)
                    for (i, p) in points.enumerated() {
                        let c = CGPoint(x: p.x * sz.width, y: (1 - p.y) * sz.height)
                        let dot = Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9))
                        ctx.fill(dot, with: .color(i == dragging ? color : theme.deep)); ctx.stroke(dot, with: .color(color), lineWidth: 1.4)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in drag(v, size: size) }.onEnded { _ in dragging = nil })
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement().accessibilityLabel(L("Curves"))
            .accessibilityValue(points.map { "\(Int($0.x * 255))→\(Int($0.y * 255))" }.joined(separator: ", "))
        }
    }

    private func drag(_ v: DragGesture.Value, size: CGSize) {
        var pts = points
        let x = min(1, max(0, v.location.x / size.width)), rawY = 1 - v.location.y / size.height, y = min(1, max(0, rawY))
        if dragging == nil {
            let start = CGPoint(x: v.startLocation.x / size.width, y: 1 - v.startLocation.y / size.height)
            if let near = pts.indices.min(by: { hypot(pts[$0].x - start.x, pts[$0].y - start.y) < hypot(pts[$1].x - start.x, pts[$1].y - start.y) }),
               hypot(pts[near].x - start.x, pts[near].y - start.y) < 0.07 { dragging = near }
            else if pts.count < 16 {
                pts.append(CurvePoint(x: x, y: y)); pts.sort { $0.x < $1.x }
                dragging = pts.firstIndex { $0.x == x && $0.y == y }
            }
        }
        guard let i = dragging, pts.indices.contains(i) else { return }
        let endpoint = i == 0 || i == pts.count - 1
        if !endpoint && (rawY < -0.08 || rawY > 1.08) { pts.remove(at: i); dragging = nil; commit(pts); return }
        // Endpoints keep their x; middle points stay between their neighbours.
        let lo = endpoint ? pts[i].x : pts[i - 1].x + 0.01, hi = endpoint ? pts[i].x : pts[i + 1].x - 0.01
        pts[i] = CurvePoint(x: min(hi, max(lo, x)), y: y)
        commit(pts)
    }

    private func commit(_ pts: [CurvePoint]) {
        var c = curves; c[channel] = ToneCurve.isIdentity(pts) && pts.count == 2 ? nil : pts
        set(c.isEmpty ? nil : c)
    }
}
