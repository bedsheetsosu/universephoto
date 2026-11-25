import Foundation

/// Animate → Layer motion → Remove drift (0.171): takes out the active layer's net travel from the
/// first to the last frame, spread evenly – a walk cycle walks on the spot, a wobbly movement that
/// slowly wanders off comes back for the loop. Wiggles, bounces and sways stay. Position and turn;
/// size and opacity stay. Works on the play range if set. One undo step. Returns frames changed.
extension Studio {
    static func withoutDrift(_ v: [Double]) -> [Double] {
        guard v.count >= 2 else { return v }
        let step = (v[v.count - 1] - v[0]) / Double(v.count - 1)
        return v.enumerated().map { $0.element - step * Double($0.offset) }
    }

    @discardableResult func removeDrift() -> Int {
        guard frames.count >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let slots = r.compactMap { i in frames[i].firstIndex { $0.id == id }.map { (i, $0) } }
        guard slots.count >= 2 else { return 0 }
        let t = slots.map { frames[$0.0][$0.1].transform }
        let xs = Studio.withoutDrift(t.map(\.x)), ys = Studio.withoutDrift(t.map(\.y)), rs = Studio.withoutDrift(t.map(\.rotation))
        var nf = frames, touched = 0
        for (k, (i, j)) in slots.enumerated() {
            var n = nf[i][j].transform
            n.x = xs[k]; n.y = ys[k]; n.rotation = rs[k]
            if nf[i][j].transform != n { nf[i][j].transform = n; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Remove drift")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
