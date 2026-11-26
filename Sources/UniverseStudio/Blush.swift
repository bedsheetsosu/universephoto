import Foundation
import CoreGraphics

/// Animation → Effects → Blush (0.268): pink cheeks on the active layer – two soft pink ovals with
/// three little slanted hatch lines each fade in over the first third, then glow gently. Follows the
/// layer. On a new layer above it. Over the play range (or all frames). One undo step.
extension Studio {
    /// Opacity of the blush at time `t` (0…1): fades in, then a gentle glow.
    static func blushAlpha(_ t: Double) -> Double {
        let fade = min(1, t / 0.3)
        return fade * (0.85 + 0.15 * sin(2 * .pi * t * 2))
    }

    static func blushStrokes(at c: CGPoint, width w: Double, alpha: Double) -> [InkStroke] {
        guard alpha > 0.01 else { return [] }
        var out = [oval(c, rx: w / 2, ry: w * 0.28, CodableColor(red: 1, green: 0.45, blue: 0.55, alpha: 0.55 * alpha))]
        let line = CodableColor(red: 0.85, green: 0.25, blue: 0.35, alpha: alpha)
        for k in -1...1 {
            let x = c.x + Double(k) * w * 0.22
            out.append(InkStroke(points: [InkPoint(x: x + w * 0.06, y: c.y - w * 0.12, pressure: 1),
                                          InkPoint(x: x - w * 0.06, y: c.y + w * 0.12, pressure: 1)], color: line, width: max(1, w * 0.05)))
        }
        return out
    }

    @discardableResult func addBlush() -> Int {
        guard frames.count >= 2, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let w = max(8, local.width * 0.22)
        let cheeks = [-1.0, 1.0].map { CGPoint(x: local.midX + $0 * local.width * 0.26, y: local.minY + local.height * 0.52) }
        checkpoint("Blush")
        let layer = ArtLayer(name: L("Blush"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let m = matrix(s.transform)
                let t = r.count > 1 ? Double(i - r.lowerBound) / Double(r.count - 1) : 1
                l.strokes = cheeks.flatMap { Studio.blushStrokes(at: $0.applying(m), width: w * s.transform.scale, alpha: Studio.blushAlpha(t)) }
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return r.count
    }
}
