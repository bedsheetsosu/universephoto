import Foundation

/// Animation → Layer effects → Wander (0.225): the active layer drifts around on a soft, random,
/// seamless path – a fly, a firefly, a balloon on a string, a leaf in the air. Unlike Float (one
/// sine), several slow waves overlap, so it never looks mechanical, and the path still closes into
/// a loop. Starts at its own position. Over the play range (or all frames). One undo step.
extension Studio {
    /// Offset for frame `k` of `n`: three overlapping waves per axis, zero at the start, a loop.
    static func wanderOffset(_ k: Int, of n: Int, radius: Double, seed: UInt64) -> (Double, Double) {
        guard n > 0 else { return (0, 0) }
        let r = shakeOffsets(count: 6, seed: seed)
        let t = 2 * Double.pi * Double(k) / Double(n)
        func axis(_ base: Int) -> Double {
            (1...3).reduce(0.0) { sum, m in
                let a = radius / Double(m) * (0.6 + 0.4 * abs(r[base + m - 1].2)), phase = r[base + m - 1].0 * .pi
                return sum + a * (sin(Double(m) * t + phase) - sin(phase))
            }
        }
        return (axis(0), axis(3) * 0.8)
    }

    @discardableResult func wanderLayer(radius: Double, seed: UInt64 = 0x3A7D) -> Int {
        guard frames.count >= 2, radius > 0, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let (dx, dy) = Studio.wanderOffset(k, of: r.count, radius: radius, seed: seed)
            guard abs(dx) > 1e-9 || abs(dy) > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                nf[i][j].transform.x += dx; nf[i][j].transform.y += dy; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Wander")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
