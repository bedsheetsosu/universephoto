import Foundation
import CoreGraphics

/// Animation → Effects → Sweat drop (0.235): the cartoon sign for nerves – a light blue drop
/// appears at the upper side of the active layer, grows, slides down its side and drips off, again
/// and again as a loop. Follows the layer if it moves. On a new layer above it. Works on the play
/// range if set. One undo step. Returns how many drops run in one loop (one at a time).
extension Studio {
    /// The drop at age `t` (0…1) of its run: (slide down 0…1, size 0…1, opacity).
    static func dropState(_ t: Double) -> (slide: Double, size: Double, alpha: Double) {
        let grow = min(1, t / 0.3)                                  // swells at the start
        let slide = t < 0.3 ? 0 : pow((t - 0.3) / 0.7, 2)            // then speeds up sliding down
        let alpha = t > 0.85 ? max(0, 1 - (t - 0.85) / 0.15) : 1
        return (slide, 0.4 + 0.6 * grow, alpha)
    }

    static func dropStrokes(at p: CGPoint, size: Double, alpha: Double) -> [InkStroke] {
        guard alpha > 0.02, size > 0.5 else { return [] }
        let blue = CodableColor(red: 0.55, green: 0.8, blue: 1, alpha: 0.9 * alpha)
        let shine = CodableColor(red: 1, green: 1, blue: 1, alpha: 0.85 * alpha)
        // A teardrop from three stacked ovals, narrowing upwards, plus a little shine.
        func oval(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ c: CodableColor) -> InkStroke {
            var o = InkStroke(points: [InkPoint(x: cx - w / 2, y: cy - h / 2, pressure: 1), InkPoint(x: cx + w / 2, y: cy + h / 2, pressure: 1)], color: c, width: 1)
            o.kind = "ellipse"; o.filled = true
            return o
        }
        return [oval(p.x, p.y - size * 0.95, size * 0.3, size * 0.5, blue),
                oval(p.x, p.y - size * 0.55, size * 0.65, size * 0.8, blue),
                oval(p.x, p.y, size * 1.1, size * 1.2, blue),
                oval(p.x - size * 0.22, p.y - size * 0.12, size * 0.22, size * 0.32, shine)]
    }

    @discardableResult func addSweatDrop(drops: Int = 2) -> Int {
        guard frames.count >= 2, drops > 0, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let size = max(6, min(local.width, local.height) * 0.15)
        let start = CGPoint(x: local.maxX - local.width * 0.08, y: local.minY + local.height * 0.18)
        let fall = local.height * 0.75
        checkpoint("Sweat drop")
        let layer = ArtLayer(name: L("Sweat drop"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let m = matrix(s.transform), k = Double(i - r.lowerBound) / Double(r.count)
                let a = k * Double(drops), t = a - a.rounded(.down)       // one drop at a time, `drops` per loop
                let st = Studio.dropState(t)
                let p = CGPoint(x: start.x + local.width * 0.04 * st.slide, y: start.y + fall * st.slide).applying(m)
                l.strokes = Studio.dropStrokes(at: p, size: size * st.size * s.transform.scale, alpha: st.alpha)
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return drops
    }
}
