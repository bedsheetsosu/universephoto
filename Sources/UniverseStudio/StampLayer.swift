import Foundation

/// Animation → Layer effects → Stamp (0.219): the active layer comes down like a rubber stamp –
/// huge and see-through at first, it slams onto its place within a few frames, and the whole
/// picture jolts on the hit. Titles, "APPROVED", a logo, a big "POW". Over the play range (or all
/// frames); after the hit it stays as it was. One undo step. Returns the frame of the hit (0 = nothing done).
extension Studio {
    /// Scale factor and opacity factor for frame `k`; the hit lands on frame `hit`.
    static func stampLook(_ k: Int, hit: Int) -> (scale: Double, alpha: Double) {
        guard hit > 0, k < hit else { return (1, 1) }
        let t = Double(k) / Double(hit), e = t * t            // speeds up towards the hit
        return (3 - 2 * e, 0.15 + 0.85 * e)
    }

    @discardableResult func stampLayer(hitAfter: Int, shake: Double = 8) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let hit = min(max(1, hitAfter), r.count - 1)
        var nf = shake > 0 ? Studio.unsharedForCamera(frames) : frames     // the jolt moves backgrounds too
        for (k, i) in r.enumerated() where k < hit {
            let look = Studio.stampLook(k, hit: hit)
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                pivotEdit(&nf[i][j], .centre) { $0.scale *= look.scale }
                nf[i][j].opacity *= look.alpha
            }
        }
        // The jolt: every layer, fading over four frames from the hit.
        let jolts = Studio.shakeOffsets(count: 4, seed: 0x57A3)
        for age in 0..<4 where hit + age < r.count {
            let i = r.lowerBound + hit + age, fade = shake * (1 - Double(age) / 4)
            for j in nf[i].indices where !nf[i][j].locked {
                nf[i][j].transform.x += jolts[age].0 * fade; nf[i][j].transform.y += jolts[age].1 * fade
            }
        }
        checkpoint("Stamp")
        frames = nf; layers = frames[frameIndex]; changed()
        return r.lowerBound + hit
    }
}
