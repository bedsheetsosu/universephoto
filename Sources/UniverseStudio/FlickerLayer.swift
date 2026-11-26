import Foundation

/// Animation → Layer effects → Flicker (0.240): the active layer flickers irregularly – short bursts
/// of dimming and dropping out between calm stretches, like a broken neon sign, a candle or a
/// failing torch. Unlike Blink it never keeps a beat. Its opacity per frame is multiplied, so it can
/// be undone in one step and stacked with fades. Over the play range (or all frames).
extension Studio {
    /// Opacity factor per frame for `n` frames; `wild` flickers more often and deeper.
    static func flickerLevels(count n: Int, wild: Bool, seed: UInt64 = 0xF11C) -> [Double] {
        var out = Array(repeating: 1.0, count: n)
        let r = shakeOffsets(count: max(1, n), seed: seed)
        var k = 0
        while k < n {
            let calm = r[k % r.count].0
            if abs(calm) < (wild ? 0.45 : 0.22) {                    // a burst starts here
                let length = 2 + Int(abs(r[k % r.count].1) * (wild ? 4 : 2))
                for j in 0..<length where k + j < n {
                    let v = abs(r[(k + j) % r.count].2)
                    out[k + j] = v < 0.35 ? 0.05 : 0.25 + 0.6 * v     // sometimes nearly out
                }
                k += length + 2
            } else { k += 1 }
        }
        return out
    }

    @discardableResult func flickerLayer(wild: Bool) -> Int {
        guard frames.count >= 3, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let levels = Studio.flickerLevels(count: r.count, wild: wild)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() where levels[k] < 1 {
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked { nf[i][j].opacity *= levels[k]; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Flicker")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
