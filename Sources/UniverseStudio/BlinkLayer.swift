import Foundation

/// Animate → Blink layer (0.133): switches the active layer on and off across the frames in a
/// steady rhythm – a blinking light, a warning sign, an alarm. It changes only that layer's
/// visibility per frame, nothing is drawn or added. "Steady" shows it again everywhere. Works on
/// the play range if one is set, otherwise all frames. One undo step.
extension Studio {
    /// Visibility pattern for a blink with toggle interval `period`: on for `period` frames, off for
    /// `period`, repeating. Index is counted from the range's start so it reads the same every run.
    static func blinkVisible(frameIndexInRange k: Int, period: Int) -> Bool {
        let p = max(1, period)
        return (k / p) % 2 == 0
    }

    @discardableResult func blinkLayer(period: Int) -> Int {
        guard !frames.isEmpty, period >= 1, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, changedAny = false
        for (k, i) in r.enumerated() {
            let vis = Studio.blinkVisible(frameIndexInRange: k, period: period)
            for j in nf[i].indices where nf[i][j].id == id {
                if nf[i][j].visible != vis { nf[i][j].visible = vis; changedAny = true }
            }
        }
        guard changedAny else { return 0 }
        checkpoint("Blink layer")
        frames = nf; layers = frames[frameIndex]; changed()
        return r.count
    }

    /// Turns the active layer back on in every frame (clears a blink).
    @discardableResult func steadyLayer() -> Int {
        guard !frames.isEmpty, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        var nf = frames, changedAny = false
        for i in nf.indices {
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].visible { nf[i][j].visible = true; changedAny = true }
        }
        guard changedAny else { return 0 }
        checkpoint("Steady layer")
        frames = nf; layers = frames[frameIndex]; changed()
        return nf.count
    }
}
