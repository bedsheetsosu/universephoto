import Foundation
import CoreGraphics

/// Animation → Effects → Impacts → Focus lines (0.295): the manga "look here!" – dark lines shoot in
/// from the edges of the picture towards the active layer (or the middle), thick at the edge and
/// pointed at the tip, leaving a clear space around it. They change every two frames so they
/// flicker with energy. On a new layer on top. Over the play range (or all frames). One undo step.
extension Studio {
    /// Lines for one moment (`seed`) around `c`: from beyond the farthest corner in to a gap of `gap`.
    static func focusLines(count: Int, centre c: CGPoint, gap: Double, reach: Double, width: Double, seed: UInt64) -> [InkStroke] {
        let o = shakeOffsets(count: count, seed: seed)
        return (0..<count).map { k in
            let a = (Double(k) + 0.5 * o[k].0) / Double(count) * 2 * .pi
            let inner = gap * (1 + 0.35 * abs(o[k].1))                 // ragged inner edge
            return InkStroke(points: [InkPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach, pressure: 1),
                                      InkPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner, pressure: 0.05)],
                             color: CodableColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.85), width: width * (0.6 + 0.4 * abs(o[k].2)))
        }
    }

    @discardableResult func addFocusLines(count: Int = 40) -> Int {
        guard frames.count >= 2, count > 0 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let w = Double(width), h = Double(height)
        var c = CGPoint(x: w / 2, y: h / 2), gap = min(w, h) * 0.3
        if let l = activeLayer, l.allFrames != true, let b = contentBounds(l) {
            let t = b.applying(matrix(l.transform))
            c = CGPoint(x: t.midX, y: t.midY); gap = max(gap * 0.5, max(t.width, t.height) * 0.6)
        }
        let reach = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), CGPoint(x: w, y: h)].map { hypot($0.x - c.x, $0.y - c.y) }.max()! + 4
        let lineWidth = max(2, min(w, h) * 0.018)
        checkpoint("Focus lines")
        let layer = ArtLayer(name: L("Focus lines"))
        for i in frames.indices {
            var l = layer
            if r.contains(i) {
                l.strokes = Studio.focusLines(count: count, centre: c, gap: gap, reach: reach, width: lineWidth, seed: 0xF0C5 &+ UInt64((i - r.lowerBound) / 2))
            }
            frames[i].append(l)
        }
        layers = frames[frameIndex]; selectedLayer = layers.count - 1
        changed()
        return r.count
    }
}
