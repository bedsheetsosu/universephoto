import Foundation

/// Animate → Merge identical frames (0.123): runs of consecutive frames with the exact same
/// drawing collapse into one held frame, their holds added up – so the animation looks the same
/// but weighs less and is easier to retime. Handy after importing a video or GIF that repeats
/// frames. Works on the play range if one is set, otherwise all frames. One undo step.
extension Studio {
    /// For each run of identical frames in `range`: the anchor's new hold, and the indices to drop.
    /// A run's hold never grows past 99 (the per-frame cap) – it keeps a frame instead, so the
    /// animation's total length is preserved exactly.
    static func mergeRuns(_ frames: [[ArtLayer]], holds: [Int], in range: ClosedRange<Int>) -> (newHolds: [Int: Int], remove: [Int]) {
        var newHolds: [Int: Int] = [:], remove: [Int] = []
        guard range.lowerBound < range.upperBound, range.upperBound < frames.count else { return (newHolds, remove) }
        var anchor = range.lowerBound, acc = max(1, holds[anchor])
        func flush() { if acc != holds[anchor] { newHolds[anchor] = acc } }
        for j in (range.lowerBound + 1)...range.upperBound {
            let hj = max(1, holds[j])
            if frames[j] == frames[anchor], acc + hj <= 99 { acc += hj; remove.append(j) }
            else { flush(); anchor = j; acc = hj }
        }
        flush()
        return (newHolds, remove)
    }

    @discardableResult func mergeIdenticalFrames() -> Int {
        guard frames.count > 1 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let holdsArr = (0..<frames.count).map { hold($0) }
        let plan = Studio.mergeRuns(frames, holds: holdsArr, in: r)
        guard !plan.remove.isEmpty else { return 0 }
        checkpoint("Merge identical frames")
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
