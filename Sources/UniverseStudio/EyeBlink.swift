import Foundation

/// Animation → Layer effects → Eye blink (0.223): the active layer – a pair of eyes on their own
/// layer – shuts for a moment now and then, squashed flat to a line around its middle and opened
/// again, at slightly irregular gaps like a real blink. Over the play range (or all frames), never
/// on the very first or last frame, so a loop doesn't blink at the seam. One undo step. Returns
/// how many blinks there are.
extension Studio {
    /// Openness (1 = open, 0.1 = shut) per frame for `n` frames, blinking about every `gap` frames.
    static func blinkOpenness(count n: Int, gap: Int, seed: UInt64 = 0xB1E) -> [Double] {
        var open = Array(repeating: 1.0, count: n)
        guard n >= 5, gap >= 4 else { return open }
        let jitter = shakeOffsets(count: n / gap + 2, seed: seed)
        var at = gap / 2, k = 0
        while at + 2 < n - 1 {
            open[at] = 0.45; open[at + 1] = 0.1; open[at + 2] = 0.55     // closing, shut, opening
            at += max(4, gap + Int((jitter[k].0 * Double(gap) * 0.35).rounded())); k += 1
        }
        return open
    }

    @discardableResult func eyeBlink(everySeconds: Double) -> Int {
        guard frames.count >= 5, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let open = Studio.blinkOpenness(count: r.count, gap: max(4, Int((fps * everySeconds).rounded())))
        let blinks = open.filter { $0 == 0.1 }.count
        guard blinks > 0 else { return 0 }
        var nf = frames
        for (k, i) in r.enumerated() where open[k] < 1 {
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                // Flat but not wider: scaleY × o, scaleX unchanged (scale √o, stretch √o).
                let o = open[k]
                pivotEdit(&nf[i][j], .centre) { t in
                    t.stretch = (t.stretch ?? 1) * o.squareRoot(); t.scale *= o.squareRoot()
                }
            }
        }
        checkpoint("Eye blink")
        frames = nf; layers = frames[frameIndex]; changed()
        return blinks
    }
}
