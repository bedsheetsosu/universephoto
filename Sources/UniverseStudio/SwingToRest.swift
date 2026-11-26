import Foundation

/// Animation → Layer effects → Swing to rest (0.217): the active layer has just been knocked – it
/// swings hard, then less and less until it is still. Hanging from its top (a sign that was hit, a
/// lamp) or standing on its bottom (a spring toy, a door stop, a tree after a gust). Over the play
/// range (or all frames), starting at its first frame. Added to its own rotation. One undo step.
extension Studio {
    /// Extra rotation in degrees for frame `k` of `n`: a damped swing, three to four swings long.
    static func swingToRest(_ k: Int, of n: Int, degrees: Double) -> Double {
        guard n >= 2 else { return 0 }
        let t = Double(k) / Double(n - 1)
        return degrees * exp(-4 * t) * sin(2 * .pi * 3.5 * t) * (t >= 1 ? 0 : 1)
    }

    @discardableResult func swingToRest(degrees: Double, hanging: Bool) -> Int {
        guard frames.count >= 2, degrees != 0, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let off = Studio.swingToRest(k, of: r.count, degrees: degrees)
            guard abs(off) > 1e-6 else { continue }
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                pivotEdit(&nf[i][j], hanging ? .top : .bottom) { $0.rotation += off }
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Swing to rest")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
