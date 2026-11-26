import Foundation

/// Animation → Layer effects → Beam (0.286): sci-fi teleport – the active layer squeezes sideways into
/// a thin upright line of light and vanishes, keeping its height (beam out), or grows back out of that
/// line (beam in). Over the play range (or all frames), around its middle. Adds onto what is there.
/// One undo step.
extension Studio {
    /// (scale, stretch, opacity) at progress `e` (0 = normal … 1 = gone): width shrinks, height stays.
    static func beamPose(_ e: Double) -> (scale: Double, stretch: Double, opacity: Double) {
        let sx = max(0.03, 1 - 0.97 * e)
        return (sx.squareRoot(), (1 / sx).squareRoot(), e < 0.8 ? 1 : e >= 1 ? 0 : max(0, 1 - (e - 0.8) / 0.2))
    }

    @discardableResult func beamLayer(out: Bool) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.count >= 2 else { return 0 }
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let t = Double(k) / Double(r.count - 1), e = out ? t * t : (1 - t) * (1 - t)
            let p = Studio.beamPose(e)
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                pivotEdit(&nf[i][j], .centre) { $0.scale *= p.scale; $0.stretch = max(0.05, min(40, ($0.stretch ?? 1) * p.stretch)) }
                nf[i][j].opacity *= p.opacity
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint(out ? "Beam out" : "Beam in")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
