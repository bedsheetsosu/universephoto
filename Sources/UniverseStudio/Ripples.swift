import Foundation
import CoreGraphics

/// Animation → Effects → Ripples (0.211): rings spread out from the middle of the active layer and
/// fade – a drop in water, a radio signal, a sonar ping, a shout. Several rings at even spacing, as
/// a seamless loop over the play range (or all frames), following the layer if it moves. `flat`
/// squeezes them into ovals lying on the ground. On a new layer below the active one. One undo
/// step. Returns how many rings there are.
extension Studio {
    /// Age 0…1 of ring `c` of `rings` in frame `k` of `n` – evenly staggered, wrapping round.
    static func rippleAge(_ c: Int, rings: Int, frame k: Int, of n: Int) -> Double {
        guard n > 0, rings > 0 else { return 0 }
        let a = Double(k) / Double(n) + Double(c) / Double(rings)
        return a - a.rounded(.down)
    }

    static func rippleStroke(centre: CGPoint, age: Double, reach: Double, flat: Bool, colour: CodableColor) -> InkStroke? {
        let alpha = colour.alpha * (1 - age) * min(1, age * 6)    // eases in, fades out
        guard alpha > 0.02 else { return nil }
        let rx = 6 + reach * age, ry = flat ? rx * 0.3 : rx
        var c = colour; c.alpha = alpha
        var s = InkStroke(points: [InkPoint(x: centre.x - rx, y: centre.y - ry, pressure: 1), InkPoint(x: centre.x + rx, y: centre.y + ry, pressure: 1)],
                          color: c, width: max(1, 4 * (1 - age)))
        s.kind = "ellipse"; s.filled = false
        return s
    }

    @discardableResult func addRipples(rings: Int = 3, flat: Bool = false, colour: CodableColor = CodableColor(red: 0.55, green: 0.8, blue: 1, alpha: 0.9)) -> Int {
        guard rings > 0, frames.count >= 2, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let anchor = flat ? CGPoint(x: local.midX, y: local.maxY) : CGPoint(x: local.midX, y: local.midY)
        let reach = max(40, max(local.width, local.height) * 1.8)
        checkpoint("Ripples")
        let layer = ArtLayer(name: L("Ripples"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let c = anchor.applying(matrix(s.transform))
                l.strokes = (0..<rings).compactMap { ring in
                    Studio.rippleStroke(centre: c, age: Studio.rippleAge(ring, rings: rings, frame: i - r.lowerBound, of: r.count), reach: reach, flat: flat, colour: colour)
                }
            }
            frames[i].insert(l, at: frames[i].firstIndex { $0.id == src.id } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return rings
    }
}
