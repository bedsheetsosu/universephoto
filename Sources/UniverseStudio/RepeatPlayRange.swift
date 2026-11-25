import Foundation

/// Animate → Edit frames → Repeat play range (0.158): copies the frames of the play range (with
/// their holds) right behind it, so one passage – a blink, a step – happens several times while the
/// rest of the animation stays as it is. The play range then covers all copies. One undo step.
/// Returns how many frames were added.
extension Studio {
    @discardableResult func repeatPlayRange(times: Int) -> Int {
        guard times >= 2, let r = Playback.clamp(playRange, count: frames.count) else { return 0 }
        let add = r.count * (times - 1)
        guard frames.count + add <= 1200 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let block = Array(frames[r]), holds = r.map { hold($0) }
        checkpoint("Repeat play range")
        for _ in 1..<times {
            let at = r.upperBound + 1
            metaInsert(at: at, holds: holds)
            frames.insert(contentsOf: block, at: at)
        }
        playRange = r.lowerBound...(r.upperBound + add)
        layers = frames[frameIndex]; changed()
        return add
    }
}
