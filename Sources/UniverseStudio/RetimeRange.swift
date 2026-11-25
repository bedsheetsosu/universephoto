import Foundation

/// Animate → Retime (0.130): slows down or speeds up a stretch of the animation by scaling how
/// long each frame holds – ×2 or ×3 for slow motion, ×½ for fast forward. No frames are added or
/// removed, so drawings stay put; only their on-screen time changes. Works on the play range if
/// one is set, otherwise all frames. Holds stay within 1…99. One undo step.
extension Studio {
    /// Each hold scaled by `factor`, rounded, kept in 1…99.
    static func retimedHolds(_ holds: [Int], in range: ClosedRange<Int>, factor: Double) -> [Int] {
        var h = holds
        guard factor > 0, range.lowerBound >= 0, range.upperBound < h.count else { return h }
        for i in range { h[i] = max(1, min(99, Int((Double(max(1, h[i])) * factor).rounded()))) }
        return h
    }

    /// Animate → Set length (0.134): scales every frame's hold so the whole animation runs about
    /// `seconds` long at the current frame rate – no frames added or removed. One undo step.
    @discardableResult func fitToDuration(seconds: Double) -> Bool {
        guard !frames.isEmpty, seconds > 0, fps > 0 else { return false }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let holdsArr = (0..<frames.count).map { hold($0) }
        let total = holdsArr.reduce(0, +)
        guard total > 0 else { return false }
        let target = max(frames.count, Int((seconds * fps).rounded()))
        let new = Studio.retimedHolds(holdsArr, in: 0...(frames.count - 1), factor: Double(target) / Double(total))
        guard new != holdsArr else { return false }
        checkpoint("Set length")
        frameHolds = new; normalizeHolds(); changed()
        return true
    }

    @discardableResult func retimeRange(factor: Double) -> Bool {
        guard frames.count > 0, factor > 0, factor != 1 else { return false }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let holdsArr = (0..<frames.count).map { hold($0) }
        let new = Studio.retimedHolds(holdsArr, in: r, factor: factor)
        guard new != holdsArr else { return false }
        checkpoint("Retime")
        frameHolds = new; normalizeHolds(); changed()
        return true
    }
}
