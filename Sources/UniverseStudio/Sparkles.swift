import Foundation
import CoreGraphics

/// Animation → Effects → Sparkles (0.207): little four-point stars around the active layer that
/// twinkle on and off at different times – something new, shiny, magic or clean. A seamless loop
/// over the play range (or all frames), on a new layer above the active one, following it if it
/// moves. One undo step. Returns how many sparkles there are.
extension Studio {
    /// Size 0…1 of sparkle `c` in frame `k` of `n`: one quick twinkle per loop, at its own moment.
    static func sparkleSize(_ c: Int, frame k: Int, of n: Int, total: Int) -> Double {
        guard n > 0, total > 0 else { return 0 }
        let phase = (Double(k) / Double(n) - Double(c) / Double(total)).truncatingRemainder(dividingBy: 1)
        let p = phase < 0 ? phase + 1 : phase
        let window = min(0.5, max(0.2, 3 / Double(n)))
        guard p < window else { return 0 }
        return sin(.pi * p / window)
    }

    static func sparkleStrokes(at c: CGPoint, size: Double, colour: CodableColor) -> [InkStroke] {
        guard size > 0.05 else { return [] }
        let arm = 3 + 9 * size, w = 1 + 2.5 * size
        return [InkStroke(points: [InkPoint(x: c.x, y: c.y - arm, pressure: 1), InkPoint(x: c.x, y: c.y + arm, pressure: 1)], color: colour, width: w),
                InkStroke(points: [InkPoint(x: c.x - arm * 0.7, y: c.y, pressure: 1), InkPoint(x: c.x + arm * 0.7, y: c.y, pressure: 1)], color: colour, width: w)]
    }

    @discardableResult func addSparkles(count: Int, colour: CodableColor = CodableColor(red: 1, green: 0.93, blue: 0.55, alpha: 1)) -> Int {
        guard count > 0, frames.count >= 2, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        // Spots around the drawing's edge, a little outside it, in layer-local space.
        let jitter = Studio.shakeOffsets(count: count, seed: 0x57A2)
        let spots: [CGPoint] = (0..<count).map { c in
            let a = 2 * Double.pi * (Double(c) + 0.5 * jitter[c].0) / Double(count)
            let reach = 0.5 + 0.18 * (jitter[c].1 + 1)
            return CGPoint(x: local.midX + cos(a) * local.width * reach, y: local.midY + sin(a) * local.height * reach)
        }
        // Twinkle in a shuffled order, so it doesn't read as one sparkle running around the drawing.
        let order = (0..<count).sorted { jitter[$0].2 < jitter[$1].2 }
        var slot = Array(repeating: 0, count: count)
        for (k, c) in order.enumerated() { slot[c] = k }
        checkpoint("Sparkles")
        let layer = ArtLayer(name: L("Sparkles"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let m = matrix(s.transform)
                l.strokes = spots.enumerated().flatMap { c, p in
                    Studio.sparkleStrokes(at: p.applying(m), size: Studio.sparkleSize(slot[c], frame: i - r.lowerBound, of: r.count, total: count), colour: colour)
                }
            }
            let at = (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count
            frames[i].insert(l, at: at)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return count
    }
}
