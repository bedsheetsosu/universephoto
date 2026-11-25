import Foundation

/// Animate → Pulse size (0.139): grows and shrinks the active layer across the frames as a seamless
/// loop – a gentle breathing or a heartbeat on top of an existing animation. The size-sibling of
/// Pulse layer (opacity) and Float layer (position). It scales the layer per frame (undo to remove;
/// running again stacks). Works on the play range if one is set, otherwise all frames. One undo.
extension Studio {
    /// Scale factor for frame `k` of `count`: 1 at the ends, 1 + `amount` at the middle, smooth.
    static func scalePulseFactor(frameIndexInRange k: Int, count: Int, amount: Double) -> Double {
        guard count >= 2 else { return 1 }
        return 1 + amount * (0.5 - 0.5 * cos(2 * .pi * Double(k) / Double(count)))
    }

    @discardableResult func scalePulseLayer(amount: Double) -> Int {
        guard frames.count >= 2, amount != 0, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let n = r.count
        var nf = frames, changedAny = false
        for (k, i) in r.enumerated() {
            let f = Studio.scalePulseFactor(frameIndexInRange: k, count: n, amount: amount)
            guard abs(f - 1) > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id {
                pivotEdit(&nf[i][j], .centre) { $0.scale *= f }
                changedAny = true
            }
        }
        guard changedAny else { return 0 }
        checkpoint("Pulse size")
        frames = nf; layers = frames[frameIndex]; changed()
        return n
    }
}
