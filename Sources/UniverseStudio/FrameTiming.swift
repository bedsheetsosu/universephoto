import Foundation

/// Animate: how long each frame stays (holds – "on twos" = 2) and reordering frames.
/// Playback and GIF/MP4/sequence export repeat a held frame; frame 1 of a hold is the drawing.
extension ArtDocument {
    /// Hold of frame `i` (1 when unset).
    func hold(_ i: Int) -> Int { max(1, frameHolds?.indices.contains(i) == true ? frameHolds![i] : 1) }
    /// Frames as played and exported: each repeated by its hold.
    var expandedFrames: [[ArtLayer]] { frames.enumerated().flatMap { i, f in Array(repeating: f, count: hold(i)) } }
}

extension Studio {
    static let holdChoices = [1, 2, 3, 4, 6, 8, 12]

    func hold(_ i: Int) -> Int { max(1, frameHolds.indices.contains(i) ? frameHolds[i] : 1) }

    /// Keeps `frameHolds` as long as `frames` (missing = 1); all ones collapse to empty.
    func normalizeHolds() {
        var h = Array(frameHolds.prefix(frames.count)).map { max(1, $0) }
        h += Array(repeating: 1, count: max(0, frames.count - h.count))
        frameHolds = h.allSatisfy { $0 == 1 } ? [] : h
        var l = Array(frameLabels.prefix(frames.count)); l += Array(repeating: "", count: max(0, frames.count - l.count))
        frameLabels = l.allSatisfy(\.isEmpty) ? [] : l
    }

    func setHold(_ n: Int, for index: Int) {
        guard frames.indices.contains(index), hold(index) != n else { return }
        checkpoint("Frame hold")
        var h = (0..<frames.count).map { hold($0) }; h[index] = max(1, min(99, n))
        frameHolds = h; normalizeHolds(); changed()
    }

    /// Moves frame `from` to position `to`; the current frame follows its drawing.
    func moveFrame(from: Int, to: Int) {
        guard frames.indices.contains(from), frames.indices.contains(to), from != to else { return }
        stopPlayback(); checkpoint("Move frame")
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let current = frameIndex
        metaMove(from: from, to: to)
        let f = frames.remove(at: from); frames.insert(f, at: to)
        if current == from { frameIndex = to }
        else if from < current && to >= current { frameIndex = current - 1 }
        else if from > current && to <= current { frameIndex = current + 1 }
        layers = frames[frameIndex]
        changed()
    }

    /// Length of the animation in seconds, holds included.
    var animationDuration: Double { Double((0..<max(1, frames.count)).reduce(0) { $0 + hold($1) }) / max(1, fps) }
}

extension Studio {
    /// Reverses the order of the frames in the play range (all frames without one); holds move
    /// with their frames and the current frame stays with its drawing.
    func reverseFrames() {
        guard frames.count > 1 else { return }
        stopPlayback(); checkpoint("Reverse frames")
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        metaReverse(r)
        frames.replaceSubrange(r, with: frames[r].reversed())
        if r.contains(frameIndex) { frameIndex = r.lowerBound + r.upperBound - frameIndex }
        layers = frames[frameIndex]
        changed()
    }
    func firstFrame() { selectFrame(Playback.clamp(playRange, count: frames.count)?.lowerBound ?? 0) }
    func lastFrame() { selectFrame(Playback.clamp(playRange, count: frames.count)?.upperBound ?? max(0, frames.count - 1)) }
}
