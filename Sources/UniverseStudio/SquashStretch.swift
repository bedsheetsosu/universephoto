import Foundation

/// Animate → Layer effects → Squash & stretch (0.179): reads the active layer's existing vertical
/// movement and deforms it to match – stretched (taller, thinner) while it moves fast, squashed
/// (flatter, wider) where it lands and turns round at the bottom. Volume is kept. Pairs with Bounce
/// over the frames. Works on the play range if set. One undo step. Returns how many frames changed.
extension Studio {
    /// Stretch per frame for the y positions `ys` (y down). Loops when `loop`.
    static func squashStretchCurve(_ ys: [Double], amount: Double) -> [Double] {
        let n = ys.count
        guard n >= 3 else { return Array(repeating: 1, count: n) }
        let at = { (i: Int) in ys[min(max(i, 0), n - 1)] }
        let speed = (0..<n).map { abs(at($0 + 1) - at($0 - 1)) / 2 }
        let turn = (0..<n).map { max(0, at($0) * 2 - at($0 - 1) - at($0 + 1)) }   // bottom turning point (y down)
        let vmax = max(speed.max() ?? 0, 1e-9), tmax = max(turn.max() ?? 0, 1e-9)
        return (0..<n).map { i in
            let st = 1 + amount * 0.35 * speed[i] / vmax - amount * 0.45 * turn[i] / tmax
            return min(1.8, max(0.45, st))
        }
    }

    @discardableResult func squashStretch(amount: Double = 1) -> Int {
        guard frames.count >= 3, amount > 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let slots = r.compactMap { i in frames[i].firstIndex { $0.id == id }.map { (i, $0) } }
        guard slots.count >= 3 else { return 0 }
        let curve = Studio.squashStretchCurve(slots.map { frames[$0.0][$0.1].transform.y }, amount: amount)
        guard curve.contains(where: { abs($0 - 1) > 1e-6 }) else { return 0 }
        var nf = frames, touched = 0
        for (k, (i, j)) in slots.enumerated() where !nf[i][j].locked {
            let v = abs(curve[k] - 1) < 1e-6 ? nil : curve[k]
            if nf[i][j].transform.stretch != v { pivotEdit(&nf[i][j], .bottom) { $0.stretch = v }; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Squash & stretch")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }

    /// Takes squash & stretch off the active layer in every frame.
    @discardableResult func clearSquashStretch() -> Int {
        guard !frames.isEmpty, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        var nf = frames, touched = 0
        for i in nf.indices { for j in nf[i].indices where nf[i][j].id == id && nf[i][j].transform.stretch != nil { pivotEdit(&nf[i][j], .bottom) { $0.stretch = nil }; touched += 1 } }
        guard touched > 0 else { return 0 }
        checkpoint("Squash & stretch")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
