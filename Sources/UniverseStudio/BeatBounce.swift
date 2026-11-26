import Foundation

/// Animation → Layer effects → Bounce to the beat (0.279): the active layer bobs in time with music –
/// on every beat it squashes down and springs up, then settles until the next one. The beats follow
/// the real time of the frames (holds included) at the chosen tempo, counted from the start of the
/// play range (or frame 1). Adds onto the motion already there. One undo step.
extension Studio {
    /// (lift 0…1, stretch) at `phase` 0…1 within a beat: squash right on the beat, then spring up and come back.
    static func beatPose(_ phase: Double) -> (lift: Double, stretch: Double) {
        let p = phase - phase.rounded(.down)
        if p < 0.12 { return (0, 1 - 0.1 * (1 - p / 0.12)) }                     // squashed on the beat
        let u = (p - 0.12) / 0.88
        return (sin(.pi * u), 1 + 0.05 * sin(.pi * u))                         // up and stretched, back down
    }

    @discardableResult func beatBounce(bpm: Double) -> Int {
        guard frames.count >= 2, bpm > 0, let id = activeLayer?.id, let local = activeLayer.flatMap(contentBounds) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let height = max(3, local.height * 0.08)
        let start = AudioTiming.time(ofFrame: r.lowerBound, fps: fps, hold: hold)
        var nf = frames, touched = 0
        for i in r {
            let t = AudioTiming.time(ofFrame: i, fps: fps, hold: hold) - start
            let pose = Studio.beatPose(t * bpm / 60)
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                pivotEdit(&nf[i][j], .bottom) { $0.stretch = max(0.3, min(3, ($0.stretch ?? 1) * pose.stretch)) }
                nf[i][j].transform.y -= height * pose.lift
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Bounce to the beat")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
