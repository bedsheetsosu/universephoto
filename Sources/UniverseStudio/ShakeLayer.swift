import Foundation

/// Animate → Layer effects → Shake layer (0.161): small random jolts of the active layer in every
/// frame – fear, cold, an impact, a rattling machine. The offsets come from a fixed seed, so the
/// same frames always shake the same way. Added on top of the existing position (and a little turn
/// when `turn` is set). Works on the play range if one is set, otherwise all frames. One undo step.
extension Studio {
    /// Deterministic offsets in −1…1 for `count` frames.
    static func shakeOffsets(count: Int, seed: UInt64 = 0x5EED) -> [(Double, Double, Double)] {
        var state = seed
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
        return (0..<count).map { _ in (next(), next(), next()) }
    }

    @discardableResult func shakeLayer(amount: Double, turn: Bool = false) -> Int {
        guard frames.count >= 2, amount > 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let o = Studio.shakeOffsets(count: r.count)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                nf[i][j].transform.x += o[k].0 * amount
                nf[i][j].transform.y += o[k].1 * amount
                if turn { nf[i][j].transform.rotation += o[k].2 * amount * 0.4 }
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Shake layer")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
