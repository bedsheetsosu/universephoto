import Foundation

/// Animate → Layer across frames → Grow over the frames (0.159): the active layer grows out of
/// nothing to its size (or shrinks away) across the existing frames, with the same soft ease as
/// Fade over the frames. Each frame's size is multiplied by the ramp, so existing size animation
/// stays. No frames are added. One undo step. Returns how many frames changed.
/// `pop` (0.167) grows with an overshoot – a little past full size, then back (ease-out-back).
extension Studio {
    static func popRamp(_ k: Int, of n: Int) -> Double {
        guard n > 1 else { return 1 }
        let t = Double(k) / Double(n - 1), c = 1.70158, u = t - 1
        return 1 + (c + 1) * u * u * u + c * u * u
    }

    @discardableResult func growLayerOverFrames(grow: Bool, pop: Bool = false) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let f = max(0.01, pop ? Studio.popRamp(grow ? k : r.count - 1 - k, of: r.count) : Studio.fadeRamp(k, of: r.count, fadeIn: grow))
            for j in nf[i].indices where nf[i][j].id == id {
                let s = nf[i][j].transform.scale * f
                if nf[i][j].transform.scale != s { pivotEdit(&nf[i][j], .centre) { $0.scale = s }; touched += 1 }
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint(pop ? "Pop" : grow ? "Grow" : "Shrink")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
