import Foundation

/// Animate → Thin frames (0.126): keeps every 2nd, 3rd or 4th drawing and lets it hold for the
/// gap, turning an "on ones" animation into one "on twos" (or threes/fours) – the hand-drawn,
/// choppier feel, with fewer frames. The total length stays the same. Works on the play range if
/// one is set, otherwise all frames. One undo step.
extension Studio {
    /// Which frames to drop, and the new hold for each kept frame, so that keeping every `step`-th
    /// frame still covers the same number of ticks. Hold is capped at 99 (the per-frame maximum).
    static func thinPlan(holds: [Int], in range: ClosedRange<Int>, step: Int) -> (newHolds: [Int: Int], remove: [Int]) {
        var newHolds: [Int: Int] = [:], remove: [Int] = []
        guard step >= 2, range.lowerBound <= range.upperBound, range.upperBound < holds.count else { return (newHolds, remove) }
        var i = range.lowerBound
        while i <= range.upperBound {
            let next = min(i + step, range.upperBound + 1)
            var acc = 0
            for j in i..<next { acc += max(1, holds[j]); if j != i { remove.append(j) } }
            acc = min(99, max(1, acc))
            if acc != holds[i] { newHolds[i] = acc }
            i = next
        }
        return (newHolds, remove)
    }

    @discardableResult func thinFrames(every step: Int) -> Int {
        guard frames.count > 1, step >= 2 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let holdsArr = (0..<frames.count).map { hold($0) }
        let plan = Studio.thinPlan(holds: holdsArr, in: r, step: step)
        guard !plan.remove.isEmpty else { return 0 }
        checkpoint("Thin frames")
        var h = holdsArr
        for (i, v) in plan.newHolds { h[i] = max(1, min(99, v)) }
        frameHolds = h
        let keep = frameIndex
        for i in plan.remove.sorted(by: >) { metaRemove(at: i); frames.remove(at: i) }
        let before = plan.remove.filter { $0 < keep }.count
        frameIndex = min(max(0, keep - before), frames.count - 1)
        layers = frames[frameIndex]; normalizeHolds(); changed()
        return plan.remove.count
    }
}
