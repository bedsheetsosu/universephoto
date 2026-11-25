import Foundation

/// Animate → Layer across frames → Grow over the frames (0.159): the active layer grows out of
/// nothing to its size (or shrinks away) across the existing frames, with the same soft ease as
/// Fade over the frames. Each frame's size is multiplied by the ramp, so existing size animation
/// stays. No frames are added. One undo step. Returns how many frames changed.
extension Studio {
    @discardableResult func growLayerOverFrames(grow: Bool) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let f = max(0.01, Studio.fadeRamp(k, of: r.count, fadeIn: grow))
            for j in nf[i].indices where nf[i][j].id == id {
                let s = nf[i][j].transform.scale * f
                if nf[i][j].transform.scale != s { nf[i][j].transform.scale = s; touched += 1 }
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint(grow ? "Grow" : "Shrink")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
