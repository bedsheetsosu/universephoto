import Foundation

/// Animate → Remove empty frames (0.148): deletes every frame in which nothing is drawn – layers
/// without strokes or pixels. Layers that are the same in all frames (a shared background) don't
/// count as content. At least one frame always stays. Works on the play range if one is set,
/// otherwise all frames. One undo step. Returns how many frames were removed.
extension Studio {
    static func frameIsEmpty(_ frame: [ArtLayer]) -> Bool {
        frame.allSatisfy { $0.allFrames == true || ($0.strokes.isEmpty && $0.imageData == nil) }
    }

    @discardableResult func removeEmptyFrames() -> Int {
        guard frames.count >= 2 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var drop = r.filter { Studio.frameIsEmpty(frames[$0]) }
        if drop.count >= frames.count { drop.removeFirst() }   // keep one frame
        guard !drop.isEmpty else { return 0 }
        checkpoint("Remove empty frames")
        let keep = frameIndex
        for i in drop.sorted(by: >) { metaRemove(at: i); frames.remove(at: i) }
        let before = drop.filter { $0 < keep }.count
        frameIndex = min(max(0, keep - before), frames.count - 1)
        layers = frames[frameIndex]; changed()
        return drop.count
    }
}
