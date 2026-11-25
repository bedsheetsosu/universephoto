import Foundation

/// Animate → Tween all frames (0.124): inserts in-betweens between *every* consecutive pair at
/// once, so a whole pose-to-pose animation turns smooth in one step. Same options as the per-frame
/// tween (speed curve, optionally morphing strokes); works on the play range if one is set,
/// otherwise all frames. One undo step.
extension Studio {
    @discardableResult func tweenAll(count: Int, curve: Easing, morph: Bool = false) -> Int {
        guard frames.count > 1, count > 0 else { return 0 }
        stopPlayback(); checkpoint("Tween all frames")
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.lowerBound < r.upperBound else { return 0 }
        let keep = frameIndex
        var inserted = 0
        // High → low, so indices at and below the pair being handled stay where they are.
        for i in stride(from: r.upperBound - 1, through: r.lowerBound, by: -1) {
            let made = Tween.frames(from: frames[i], to: frames[i + 1], count: count, curve: curve, morph: morph)
            guard !made.isEmpty else { continue }
            metaInsert(at: i + 1, holds: Array(repeating: 1, count: made.count))
            frames.insert(contentsOf: made, at: i + 1)
            inserted += made.count
        }
        // Each pair that sits before the current frame pushed it right by `count`.
        let pairsBelow = max(0, min(keep - 1, r.upperBound - 1) - r.lowerBound + 1)
        frameIndex = min(keep + count * pairsBelow, frames.count - 1)
        layers = frames[frameIndex]; changed()
        return inserted
    }
}
