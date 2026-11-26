import Foundation
import CoreGraphics

/// Animation → Effects → Emotion mark (0.237): the cartoon mark next to a head – a "!" for surprise,
/// a "?" for confusion or the red cross-shaped vein for anger. It pops in at the upper right of the
/// active layer with a little overshoot and then throbs, following the layer if it moves. On a new
/// layer above it. Over the play range (or all frames). One undo step.
enum EmotionMark: String, CaseIterable, Identifiable {
    case surprise, confusion, anger
    var id: String { rawValue }
    var title: String { switch self { case .surprise: "Surprise (!)"; case .confusion: "Confusion (?)"; case .anger: "Anger (vein)" } }
}

extension Studio {
    /// Size factor for frame `k` of `n`: pops in over the first frames with an overshoot, then throbs.
    static func markScale(_ k: Int, of n: Int, fps: Double) -> Double {
        let popFrames = max(2, Int((fps * 0.25).rounded()))
        if k < popFrames {
            let t = Double(k + 1) / Double(popFrames)
            return t < 0.7 ? t / 0.7 * 1.3 : 1.3 - 0.3 * (t - 0.7) / 0.3      // up to 1.3, settle to 1
        }
        let beat = Double(k - popFrames) / max(1, fps * 0.5)                   // two throbs a second
        return 1 + 0.12 * max(0, sin(2 * .pi * beat))
    }

    static func markStrokes(_ mark: EmotionMark, at c: CGPoint, size: Double) -> [InkStroke] {
        switch mark {
        case .surprise, .confusion:
            var t = InkStroke(points: [InkPoint(x: c.x, y: c.y - size * 0.7, pressure: 1)],
                              color: mark == .surprise ? CodableColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1) : CodableColor(red: 0.2, green: 0.35, blue: 0.85, alpha: 1),
                              width: size * 1.4)
            t.kind = "text"; t.text = mark == .surprise ? "!" : "?"; t.fontName = "Helvetica-Bold"; t.textAlign = "center"
            return [t]
        case .anger:
            // Four bent strokes around a gap – the classic cross-shaped vein.
            let red = CodableColor(red: 0.88, green: 0.1, blue: 0.12, alpha: 1), w = max(2, size * 0.16), g = size * 0.14, a = size * 0.5
            return [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].map { sx, sy in
                InkStroke(points: [InkPoint(x: c.x + sx * g, y: c.y + sy * a, pressure: 1),
                                   InkPoint(x: c.x + sx * g * 1.4, y: c.y + sy * g * 1.4, pressure: 1),
                                   InkPoint(x: c.x + sx * a, y: c.y + sy * g, pressure: 1)], color: red, width: w)
            }
        }
    }

    @discardableResult func addEmotionMark(_ mark: EmotionMark) -> Int {
        guard frames.count >= 2, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let base = max(14, min(local.width, local.height) * 0.3)
        let spot = CGPoint(x: local.maxX + base * 0.2, y: local.minY - base * 0.1)
        checkpoint("Emotion mark")
        let layer = ArtLayer(name: L(mark.title))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let size = base * Studio.markScale(i - r.lowerBound, of: r.count, fps: fps) * s.transform.scale
                l.strokes = Studio.markStrokes(mark, at: spot.applying(matrix(s.transform)), size: size)
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return r.count
    }
}
