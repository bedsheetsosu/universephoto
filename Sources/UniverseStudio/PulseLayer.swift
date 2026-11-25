import Foundation

/// Animate → Pulse layer (0.136): fades the active layer's opacity up and down across the frames
/// as a seamless loop – a soft glow or breathing. The smooth sibling of Blink layer; it changes
/// only that layer's opacity per frame, nothing is drawn or added. "None" sets it fully opaque
/// again. Works on the play range if one is set, otherwise all frames. One undo step.
extension Studio {
    /// Opacity for frame `k` of `count` in the range: one smooth pulse over the whole range, so the
    /// first and last frames match and the loop has no jump. Dips to `floor` at the middle.
    static func pulseOpacity(frameIndexInRange k: Int, count: Int, floor: Double) -> Double {
        guard count >= 2 else { return 1 }
        let phase = 0.5 + 0.5 * cos(2 * .pi * Double(k) / Double(count))   // 1 at the start, 0 at the middle
        return max(0, min(1, floor + (1 - floor) * phase))
    }

    @discardableResult func pulseLayer(floor: Double) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, changedAny = false
        let n = r.count
        for (k, i) in r.enumerated() {
            let o = Studio.pulseOpacity(frameIndexInRange: k, count: n, floor: floor)
            for j in nf[i].indices where nf[i][j].id == id {
                if abs(nf[i][j].opacity - o) > 1e-9 { nf[i][j].opacity = o; changedAny = true }
            }
        }
        guard changedAny else { return 0 }
        checkpoint("Pulse layer")
        frames = nf; layers = frames[frameIndex]; changed()
        return n
    }

    /// Sets the active layer back to full opacity in every frame (clears a pulse).
    @discardableResult func unpulseLayer() -> Int {
        guard !frames.isEmpty, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        var nf = frames, changedAny = false
        for i in nf.indices {
            for j in nf[i].indices where nf[i][j].id == id && nf[i][j].opacity < 1 { nf[i][j].opacity = 1; changedAny = true }
        }
        guard changedAny else { return 0 }
        checkpoint("Clear pulse")
        frames = nf; layers = frames[frameIndex]; changed()
        return nf.count
    }
}
