import Foundation

/// Animate → Layer across frames → Motion strength (0.152): exaggerates or calms the active layer's
/// movement. Position, turn and size are scaled around their average over the frames, so a sway
/// swings wider or a bounce gets smaller while the motion keeps its timing. Opacity stays. Works
/// on the play range if one is set, otherwise all frames. One undo step. Returns frames changed.
extension Studio {
    static func amplified(_ values: [Double], factor: Double) -> [Double] {
        guard !values.isEmpty else { return values }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.map { mean + ($0 - mean) * factor }
    }

    @discardableResult func amplifyMotion(factor: Double) -> Int {
        guard frames.count >= 2, factor >= 0, factor != 1, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let slots = r.compactMap { i in frames[i].firstIndex { $0.id == id }.map { (i, $0) } }
        guard slots.count >= 2 else { return 0 }
        let t = slots.map { frames[$0.0][$0.1].transform }
        let xs = Studio.amplified(t.map(\.x), factor: factor), ys = Studio.amplified(t.map(\.y), factor: factor)
        let rs = Studio.amplified(t.map(\.rotation), factor: factor)
        let ss = Studio.amplified(t.map(\.scale), factor: factor).map { max(0.01, $0) }
        var nf = frames, touched = 0
        for (k, (i, j)) in slots.enumerated() {
            let n = LayerTransform(x: xs[k], y: ys[k], scale: ss[k], rotation: rs[k])
            if nf[i][j].transform != n { nf[i][j].transform = n; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Motion strength")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
