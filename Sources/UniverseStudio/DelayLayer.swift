import Foundation

/// Animate → Layer across frames → Delay layer (0.151): the active layer runs a few frames behind
/// (or ahead of) the rest – overlapping action, e.g. hair or a tail that follows a moment later.
/// `wrap` treats the animation as a loop, so the shifted frames come round from the end; otherwise
/// the first (or last) state is held. Works on the play range if one is set, otherwise all frames.
/// One undo step. Returns how many frames changed.
extension Studio {
    /// The source index for frame `i` when shifted by `offset` in `range`.
    static func delaySource(_ i: Int, offset: Int, in range: ClosedRange<Int>, wrap: Bool) -> Int {
        let n = range.count, k = i - range.lowerBound - offset
        return range.lowerBound + (wrap ? ((k % n) + n) % n : min(max(k, 0), n - 1))
    }

    @discardableResult func delayLayer(by offset: Int, wrap: Bool = true) -> Int {
        guard frames.count >= 2, offset != 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.count >= 2, r.allSatisfy({ i in frames[i].contains { $0.id == id } }) else { return 0 }
        let old = frames
        var nf = frames, touched = 0
        for i in r {
            let src = Studio.delaySource(i, offset: offset, in: r, wrap: wrap)
            guard let layer = old[src].first(where: { $0.id == id }), let j = nf[i].firstIndex(where: { $0.id == id }) else { continue }
            if nf[i][j] != layer { nf[i][j] = layer; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Delay layer")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
