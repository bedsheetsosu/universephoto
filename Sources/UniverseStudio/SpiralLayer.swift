import Foundation

/// Animation → Layer effects → Spiral (0.216): the active layer whirls in on a narrowing spiral and
/// lands on its own position at the end – or starts there and whirls out. It grows from small as it
/// comes in (shrinks going out) and turns with the spiral: a leaf caught by the wind, a magic
/// entrance, something sucked down a drain. Added to its own motion. Works on the play range if set.
/// One undo step. Returns how many frames changed.
extension Studio {
    /// Offset, scale factor and extra rotation for frame `k` of `n` when coming in over `turns` turns.
    static func spiralIn(_ k: Int, of n: Int, radius: Double, turns: Double) -> (dx: Double, dy: Double, scale: Double, spin: Double) {
        guard n >= 2 else { return (0, 0, 1, 0) }
        let t = Double(k) / Double(n - 1)                 // 0 … 1, lands exactly on the last frame
        let left = 1 - t, ease = left * left * (3 - 2 * left)   // smooth: slows down as it arrives
        let a = 2 * Double.pi * turns * ease
        return (radius * ease * cos(a), radius * ease * sin(a), 1 - 0.8 * ease, -360 * turns * ease)
    }

    @discardableResult func spiralLayer(radius: Double, turns: Double, out: Bool = false) -> Int {
        guard frames.count >= 2, radius > 0, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let s = Studio.spiralIn(out ? r.count - 1 - k : k, of: r.count, radius: radius, turns: turns)
            guard abs(s.dx) > 1e-9 || abs(s.dy) > 1e-9 || abs(s.scale - 1) > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                pivotEdit(&nf[i][j], .centre) { $0.scale *= s.scale; $0.rotation += s.spin }
                nf[i][j].transform.x += s.dx; nf[i][j].transform.y += s.dy
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Spiral")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
