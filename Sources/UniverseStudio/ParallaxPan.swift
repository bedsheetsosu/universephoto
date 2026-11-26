import Foundation

/// Animation → Effects → Camera → Parallax pan (0.245): the camera glides sideways and the layers
/// move at different speeds by their place in the stack – the bottom one (far away) barely, the top
/// one (close) the most – which gives a flat drawing depth. Soft ease, over the existing frames (or
/// the play range). Locked layers stay put; layers that were the same in all frames get a copy per
/// frame (0.246). One undo step.
extension Studio {
    /// Depth factor per layer index for `count` layers: 0.15 at the bottom up to 1 at the top.
    static func parallaxDepth(_ index: Int, of count: Int) -> Double {
        guard count > 1 else { return 1 }
        return 0.15 + 0.85 * Double(index) / Double(count - 1)
    }

    @discardableResult func parallaxPan(distance: Double) -> Int {
        guard frames.count >= 2, distance != 0 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = Studio.unsharedForCamera(frames), touched = 0
        for (k, i) in r.enumerated() {
            let e = Studio.fadeRamp(k, of: r.count, fadeIn: true)          // soft start and stop
            let n = nf[i].count
            for j in nf[i].indices where !nf[i][j].locked {
                let dx = -distance * e * Studio.parallaxDepth(j, of: n)
                guard abs(dx) > 1e-9 else { continue }
                nf[i][j].transform.x += dx; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Parallax pan")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
