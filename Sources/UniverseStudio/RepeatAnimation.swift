import Foundation

/// Animate → Repeat animation (0.142): appends copies of the whole animation so the sequence plays
/// through several times in a row – handy to turn one cycle into a longer clip for export. Frame
/// timings and markers come along. Capped so the total stays at most 1200 frames. One undo step.
extension Studio {
    @discardableResult func repeatAnimation(times: Int) -> Int {
        let baseCount = frames.count
        guard baseCount >= 1, times >= 2, baseCount * times <= 1200 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let srcFrames = frames
        let srcHolds = (0..<baseCount).map { hold($0) }
        checkpoint("Repeat animation")
        for _ in 1..<times {
            metaInsert(at: frames.count, holds: srcHolds)
            frames.append(contentsOf: srcFrames)
        }
        changed()
        return frames.count
    }
}
