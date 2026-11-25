import Foundation

/// Animate → Retime → Slow start / Slow end (0.143): ramps the holds across a stretch so it eases in
/// (the first frames stay longest, then it speeds up) or eases out (it slows down and settles). No
/// frames are added or removed; only how long each one stays. Works on the play range if one is set,
/// otherwise all frames. Holds stay within 1…99. One undo step.
extension Studio {
    /// Extra ticks for frame `k` of `count`: `extra` at the slow end, falling linearly to 0.
    static func rampExtra(frameIndexInRange k: Int, count: Int, extra: Int, slowStart: Bool) -> Int {
        guard count >= 2, extra > 0 else { return 0 }
        let u = Double(k) / Double(count - 1)
        return Int((Double(extra) * (slowStart ? 1 - u : u)).rounded())
    }

    @discardableResult func rampTiming(slowStart: Bool, extra: Int = 3) -> Bool {
        guard frames.count >= 2, extra > 0 else { return false }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let old = (0..<frames.count).map { hold($0) }
        var h = old
        for (k, i) in r.enumerated() {
            h[i] = max(1, min(99, h[i] + Studio.rampExtra(frameIndexInRange: k, count: r.count, extra: extra, slowStart: slowStart)))
        }
        guard h != old else { return false }
        checkpoint(slowStart ? "Slow start" : "Slow end")
        frameHolds = h; normalizeHolds(); changed()
        return true
    }
}
