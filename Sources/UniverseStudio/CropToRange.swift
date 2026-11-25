import Foundation

/// Animate → Crop to play range (0.145): keeps only the frames inside the play range and deletes the
/// rest – to keep one section as its own animation. Timings, markers and the pinned reference move
/// with their frames; the play range is cleared afterwards (it now covers everything). One undo step.
extension Studio {
    @discardableResult func cropToPlayRange() -> Int {
        guard let r = Playback.clamp(playRange, count: frames.count), r.count < frames.count else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        checkpoint("Crop to play range")
        let keep = frameIndex
        let drop = (0..<frames.count).filter { !r.contains($0) }
        for i in drop.sorted(by: >) { metaRemove(at: i); frames.remove(at: i) }
        frameIndex = r.contains(keep) ? keep - r.lowerBound : (keep < r.lowerBound ? 0 : frames.count - 1)
        playRange = nil
        layers = frames[frameIndex]; changed()
        return drop.count
    }
}
