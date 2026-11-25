import Foundation

/// Animate → Layer across frames → Fade over the frames (0.156): the active layer fades in or out
/// across the existing frames (or the play range), with a soft ease. Each frame's opacity is
/// multiplied by the ramp, so a layer already at 50 % fades between 0 and 50 %. Unlike the Fade
/// motion preset, no frames are added. One undo step. Returns how many frames changed.
extension Studio {
    static func fadeRamp(_ k: Int, of n: Int, fadeIn: Bool) -> Double {
        guard n > 1 else { return 1 }
        let t = Double(k) / Double(n - 1), e = t * t * (3 - 2 * t)
        return fadeIn ? e : 1 - e
    }

    @discardableResult func fadeLayerOverFrames(fadeIn: Bool) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            for j in nf[i].indices where nf[i][j].id == id {
                let o = nf[i][j].opacity * Studio.fadeRamp(k, of: r.count, fadeIn: fadeIn)
                if nf[i][j].opacity != o { nf[i][j].opacity = o; touched += 1 }
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint(fadeIn ? "Fade in" : "Fade out")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
