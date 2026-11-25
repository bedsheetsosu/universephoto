import Foundation

/// Animate → Layer motion → Out of step (0.175): every selected layer gets its own time offset in
/// its loop, spread evenly but shuffled, so copies of the same animation – lights, leaves, a crowd
/// – stop moving in lockstep. Each layer keeps its own movement and drawings, only shifted in time.
/// Works on the play range if set. One undo step. Returns how many layers were shifted.
extension Studio {
    /// Offsets 0..<frameCount for `count` layers: evenly spread, then shuffled with a fixed seed.
    static func desyncOffsets(count: Int, frameCount: Int) -> [Int] {
        guard count > 0, frameCount > 1 else { return Array(repeating: 0, count: max(0, count)) }
        var o = (0..<count).map { $0 * frameCount / count }
        var state: UInt64 = 0xD35C
        for i in stride(from: o.count - 1, to: 0, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            o.swapAt(i, Int((state >> 33) % UInt64(i + 1)))
        }
        return o
    }

    @discardableResult func desyncSelectedLayers() -> Int {
        guard frames.count >= 2 else { return 0 }
        let ids = layers.map(\.id).filter { selectedIDs.contains($0) }
        guard ids.count >= 2 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.count >= 2 else { return 0 }
        let offsets = Studio.desyncOffsets(count: ids.count, frameCount: r.count)
        let old = frames
        var nf = frames, moved = 0
        for (id, off) in zip(ids, offsets) where off != 0 {
            guard r.allSatisfy({ i in old[i].contains { $0.id == id } }) else { continue }
            var changedAny = false
            for i in r {
                let src = Studio.delaySource(i, offset: off, in: r, wrap: true)
                guard let l = old[src].first(where: { $0.id == id }), let j = nf[i].firstIndex(where: { $0.id == id }) else { continue }
                if nf[i][j] != l { nf[i][j] = l; changedAny = true }
            }
            if changedAny { moved += 1 }
        }
        guard moved > 0 else { return 0 }
        checkpoint("Out of step")
        frames = nf; layers = frames[frameIndex]; changed()
        return moved
    }
}
