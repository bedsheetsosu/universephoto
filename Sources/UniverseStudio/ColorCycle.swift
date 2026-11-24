import Foundation

/// Animation → Colour cycle (0.105): one frame in, a seamless loop out – the colours of the
/// strokes, shapes and text on the active layer run once around the colour wheel (or pulse
/// towards a second colour and back). Pixel content keeps its colours.
enum ColorCycle {
    /// `c` with its hue turned by `turns` (1 = full circle); grey stays grey.
    static func rotate(_ c: CodableColor, _ turns: Double) -> CodableColor {
        let r = c.red, g = c.green, b = c.blue, mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 1e-6 else { return c }
        var h: Double
        if mx == r { h = (g - b) / d } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h = (h / 6 + turns).truncatingRemainder(dividingBy: 1); if h < 0 { h += 1 }
        let s = d / mx, v = mx, i = floor(h * 6), f = h * 6 - i
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (nr, ng, nb): (Double, Double, Double) = switch Int(i) % 6 {
        case 0: (v, t, p); case 1: (q, v, p); case 2: (p, v, t); case 3: (p, q, v); case 4: (t, p, v); default: (v, p, q) }
        return CodableColor(red: nr, green: ng, blue: nb, alpha: c.alpha)
    }
}

extension Studio {
    /// Replaces the current frame with `count` looping frames. `to` given: pulse towards that
    /// colour and back; otherwise one turn around the colour wheel.
    @discardableResult func colorCycle(count: Int, to: CodableColor? = nil) -> Int {
        guard count > 1, let layer = activeLayer, layer.strokes.contains(where: { !$0.isEraser && $0.imageData == nil }) else { return 0 }
        stopPlayback(); checkpoint("Colour cycle")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let source = frames[frameIndex], id = layer.id
        let made: [[ArtLayer]] = (0..<count).map { k in
            let t = Double(k) / Double(count)
            return source.map { l in
                guard l.id == id else { return l }
                var m = l
                for i in m.strokes.indices where !m.strokes[i].isEraser && m.strokes[i].imageData == nil {
                    let c = m.strokes[i].color
                    m.strokes[i].color = to.map { StrokeMorph.mix(c, CodableColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: c.alpha), (1 - cos(t * 2 * .pi)) / 2) } ?? ColorCycle.rotate(c, t)
                }
                return m
            }
        }
        frames[frameIndex] = made[0]
        metaInsert(at: frameIndex + 1, holds: Array(repeating: 1, count: made.count - 1))
        frames.insert(contentsOf: made.dropFirst(), at: frameIndex + 1)
        layers = frames[frameIndex]
        changed()
        return made.count
    }
}
