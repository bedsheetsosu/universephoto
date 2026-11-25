import Foundation

/// Animate → Layer across frames → Smooth motion (0.153): takes the jitter out of the active
/// layer's movement with a moving average over neighbouring frames – handy after React to sound or
/// hand-placed keys. `loop` treats the animation as a cycle (the ends blend into each other);
/// otherwise the first and last frame stay where they are. Position, turn and size; opacity stays.
/// Works on the play range if one is set, otherwise all frames. One undo step.
extension Studio {
    static func smoothed(_ v: [Double], passes: Int, loop: Bool) -> [Double] {
        guard v.count >= 3 else { return v }
        var out = v
        for _ in 0..<max(1, passes) {
            let p = out
            for i in p.indices {
                if !loop && (i == 0 || i == p.count - 1) { continue }
                let a = p[(i - 1 + p.count) % p.count], b = p[(i + 1) % p.count]
                out[i] = (a + 2 * p[i] + b) / 4
            }
        }
        return out
    }

    @discardableResult func smoothMotion(passes: Int = 2, loop: Bool = false) -> Int {
        guard frames.count >= 3, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let slots = r.compactMap { i in frames[i].firstIndex { $0.id == id }.map { (i, $0) } }
        guard slots.count >= 3 else { return 0 }
        let t = slots.map { frames[$0.0][$0.1].transform }
        let f = { (k: KeyPath<LayerTransform, Double>) in Studio.smoothed(t.map { $0[keyPath: k] }, passes: passes, loop: loop) }
        let xs = f(\.x), ys = f(\.y), rs = f(\.rotation), ss = f(\.scale)
        var nf = frames, touched = 0
        for (k, (i, j)) in slots.enumerated() {
            let n = LayerTransform(x: xs[k], y: ys[k], scale: ss[k], rotation: rs[k])
            if nf[i][j].transform != n { nf[i][j].transform = n; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Smooth motion")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
