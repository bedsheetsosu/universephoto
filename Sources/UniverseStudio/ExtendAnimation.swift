import Foundation

/// Animate → Edit frames → Extend (0.195): appends copies of the last frame – room for a layer
/// effect (bounce, burst, wipe …) to play out after the drawn part. The new frames become the play
/// range, so the next effect lands right there. One undo step. Returns how many frames were added.
extension Studio {
    @discardableResult func extendAnimation(by count: Int) -> Int {
        guard count > 0, frames.count + count <= 10000 else { return 0 }
        stopPlayback()
        if frames.isEmpty { frames = [layers] }
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        checkpoint("Extend animation")
        let last = frames.count - 1
        metaInsert(at: last + 1, holds: Array(repeating: 1, count: count))
        frames.append(contentsOf: Array(repeating: frames[last], count: count))
        playRange = last...(frames.count - 1)       // from the last drawn frame, so a move starts there
        layers = frames[frameIndex]; changed()
        return count
    }
}
