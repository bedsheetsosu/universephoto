import Foundation
import CoreGraphics

/// Animation → Effects → Aura (0.274): a soft glow behind the active layer that breathes in and out –
/// magic, holy, charged up. Nine faint ovals in the brush colour (gold if that is very dark)
/// stacked from big to small, so it is strongest in the middle. Two pulses per loop, seamless over the play
/// range (or all frames). Follows the layer. On a new layer below it. One undo step.
extension Studio {
    /// Glow colour for a brush colour: very dark ones become warm gold.
    static func glowColour(_ c: CodableColor) -> CodableColor {
        c.red * 0.3 + c.green * 0.59 + c.blue * 0.11 < 0.2 ? CodableColor(red: 1, green: 0.8, blue: 0.25, alpha: 1) : c
    }

    static func auraStrokes(around b: CGRect, pulse: Double, colour: CodableColor) -> [InkStroke] {
        (0..<9).map { k in
            let grow = (1.1 - Double(k) * 0.12) * (1 + 0.12 * pulse)
            var c = colour; c.alpha = 0.05
            return oval(CGPoint(x: b.midX, y: b.midY), rx: b.width / 2 * (1 + grow), ry: b.height / 2 * (1 + grow), c)
        }
    }

    @discardableResult func addAura() -> Int {
        guard frames.count >= 2, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let colour = Studio.glowColour(color)
        checkpoint("Aura")
        let layer = ArtLayer(name: L("Aura"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let t = Double(i - r.lowerBound) / Double(r.count)
                let b = local.applying(matrix(s.transform))
                l.strokes = Studio.auraStrokes(around: b, pulse: sin(2 * .pi * t * 2), colour: colour)
            }
            frames[i].insert(l, at: frames[i].firstIndex { $0.id == src.id } ?? 0)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return r.count
    }
}
