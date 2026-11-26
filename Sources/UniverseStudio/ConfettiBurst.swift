import Foundation
import CoreGraphics

/// Animation → Effects → Burst (0.188): a one-off pop of confetti or sparks from the middle of the
/// active layer (or the canvas) – the pieces fly out, fall with gravity and fade at the end. On a
/// new layer on top; one undo step. From a single frame it makes the frames first (`count`);
/// on an animation it plays over the frames already there (or the play range).
enum BurstStyle: String, CaseIterable, Identifiable {
    case confetti, sparks, hearts
    var id: String { rawValue }
    var title: String { switch self { case .confetti: "Confetti burst"; case .sparks: "Spark burst"; case .hearts: "Heart burst" } }
    var symbol: String { switch self { case .confetti: "party.popper"; case .sparks: "sparkles"; case .hearts: "heart" } }
}

extension Studio {
    /// Strokes of the burst at progress `t` (0…1) around `c`, for a canvas `size` across.
    static func burstStrokes(_ style: BurstStyle, t: Double, centre c: CGPoint, size: Double, seed: UInt64 = 11) -> [InkStroke] {
        var g = Weather.SplitMix(seed)
        // Hearts (0.276): fewer, bigger, and they float up instead of falling.
        let n = style == .confetti ? 70 : style == .hearts ? 18 : 50, reach = size * (style == .hearts ? 0.3 : 0.45)
        let gravity = size * (style == .hearts ? -0.25 : 0.5)
        let fade = t < 0.7 ? 1 : max(0, 1 - (t - 0.7) / 0.3)
        guard t > 0, fade > 0 else { return [] }
        return (0..<n).map { k in
            let a = g.next() * 2 * .pi, v = reach * (0.45 + 0.55 * g.next()), spin = g.next()
            let out = 1 - pow(1 - t, 2)                                  // fast start, slowing down
            let x = c.x + cos(a) * v * out, y = c.y + sin(a) * v * out + gravity * t * t
            func pt(_ x: Double, _ y: Double) -> InkPoint { InkPoint(x: x, y: y, pressure: 1) }
            switch style {
            case .confetti:
                let base = Weather.confettiColors[k % Weather.confettiColors.count]
                let tumble = (t * 4 + spin) * 2 * .pi, len = 7 * (0.35 + 0.65 * abs(cos(tumble)))
                return InkStroke(points: [pt(x - len / 2, y), pt(x + len / 2, y + sin(tumble) * 2)],
                                 color: CodableColor(red: base.red, green: base.green, blue: base.blue, alpha: fade), width: 3.5)
            case .hearts:
                let pinks = [CodableColor(red: 0.93, green: 0.25, blue: 0.4, alpha: fade), CodableColor(red: 1, green: 0.5, blue: 0.65, alpha: fade),
                             CodableColor(red: 0.85, green: 0.1, blue: 0.25, alpha: fade)]
                var h = InkStroke(points: [pt(x - 6, y - 8)], color: pinks[k % 3], width: size * 0.04 * (0.7 + 0.6 * spin))
                h.kind = "text"; h.text = "♥"
                return h
            case .sparks:
                let tail = 10 * (1 - t)
                return InkStroke(points: [pt(x - cos(a) * tail, y - sin(a) * tail), pt(x, y)],
                                 color: CodableColor(red: 1, green: 0.85 - 0.3 * t, blue: 0.4 - 0.3 * t, alpha: fade), width: 2.2)
            }
        }
    }

    @discardableResult func addBurst(_ style: BurstStyle, count: Int) -> Int {
        stopPlayback()
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        // Centre: the middle of the active layer's drawing, else the canvas.
        var c = CGPoint(x: Double(width) / 2, y: Double(height) / 2)
        if let l = activeLayer, let box = contentBounds(l) { c = CGPoint(x: box.midX, y: box.midY).applying(matrix(l.transform)) }
        checkpoint("Burst")
        if frames.count == 1 {
            guard count > 1 else { return 0 }
            metaInsert(at: 1, holds: Array(repeating: 1, count: count - 1))
            frames += Array(repeating: frames[0], count: count - 1)
        }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let layer = ArtLayer(name: L(style.title)), size = Double(max(width, height))
        for i in frames.indices {
            var l = layer
            if r.contains(i) { l.strokes = Studio.burstStrokes(style, t: Double(i - r.lowerBound) / Double(max(1, r.count - 1)), centre: c, size: size) }
            frames[i].append(l)
        }
        layers = frames[frameIndex]; selectedLayer = layers.count - 1
        changed()
        return frames.count
    }
}
