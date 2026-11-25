import Foundation

/// Animate → Edit frames → Turn holds into frames (0.194): every frame that holds for several ticks
/// becomes that many real frames on ones – same timing, but now each tick is its own frame, so the
/// layer effects (bounce, spin, fade …) move smoothly through it instead of jumping. Frame labels
/// stay on the first copy. Works on the play range if set. One undo step. Returns frames added.
extension Studio {
    @discardableResult func expandHolds() -> Int {
        guard !frames.isEmpty else { return 0 }
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let extra = r.reduce(0) { $0 + hold($1) - 1 }
        guard extra > 0, frames.count + extra <= 10000 else { return 0 }
        stopPlayback()
        checkpoint("Turn holds into frames")
        let current = frameIndex
        var shiftBefore = 0
        for i in r.reversed() {
            let h = hold(i)
            guard h > 1 else { continue }
            setHoldQuietly(1, at: i)
            metaInsert(at: i + 1, holds: Array(repeating: 1, count: h - 1))
            frames.insert(contentsOf: Array(repeating: frames[i], count: h - 1), at: i + 1)
            if i < current { shiftBefore += h - 1 }
        }
        frameIndex = min(current + shiftBefore, frames.count - 1)
        if let pr = playRange { playRange = pr.lowerBound...(pr.upperBound + extra) }
        layers = frames[frameIndex]; changed()
        return extra
    }

    private func setHoldQuietly(_ n: Int, at i: Int) {
        var h = (0..<frames.count).map { hold($0) }
        guard h.indices.contains(i) else { return }
        h[i] = n; frameHolds = h; normalizeHolds()
    }
}
