import Foundation

/// Animate → Float layer (0.138): lays a soft, seamless drift over an existing animation – the
/// active layer gently bobs up and down (or side to side) across the frames, a secondary motion on
/// top of whatever is already there. The offset is a sine that returns to zero, so it loops without
/// a jump. It adds to the layer's position per frame (undo to remove; running again stacks). Works
/// on the play range if one is set, otherwise all frames. One undo step.
extension Studio {
    /// Position offset for frame `k` of `count`: one sine period over the range, zero at the ends.
    static func floatOffset(frameIndexInRange k: Int, count: Int, amplitude: Double) -> Double {
        guard count >= 2 else { return 0 }
        return amplitude * sin(2 * .pi * Double(k) / Double(count))
    }

    @discardableResult func floatLayer(amplitude: Double, horizontal: Bool) -> Int {
        guard frames.count >= 2, amplitude != 0, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let n = r.count
        var nf = frames, changedAny = false
        for (k, i) in r.enumerated() {
            let off = Studio.floatOffset(frameIndexInRange: k, count: n, amplitude: amplitude)
            guard abs(off) > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id {
                if horizontal { nf[i][j].transform.x += off } else { nf[i][j].transform.y += off }
                changedAny = true
            }
        }
        guard changedAny else { return 0 }
        checkpoint("Float layer")
        frames = nf; layers = frames[frameIndex]; changed()
        return n
    }
}
