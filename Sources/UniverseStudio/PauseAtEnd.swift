import Foundation

/// Animate → Edit frames → Pause at the end (0.168): the last frame holds longer, so a looping GIF
/// or video rests a moment before it starts again. Adds to the hold the last frame already has
/// (capped at the hold limit of 99 ticks). One undo step. Returns the new hold of the last frame.
extension Studio {
    @discardableResult func addPauseAtEnd(seconds: Double) -> Int {
        guard !frames.isEmpty, seconds > 0 else { return 0 }
        let last = frames.count - 1, old = hold(last)
        let n = min(99, old + max(1, Int((fps * seconds).rounded())))
        guard n != old else { return old }
        stopPlayback()
        checkpoint("Pause at the end")
        var h = (0..<frames.count).map { hold($0) }
        h[last] = n
        frameHolds = h; normalizeHolds(); changed()
        return n
    }
}
