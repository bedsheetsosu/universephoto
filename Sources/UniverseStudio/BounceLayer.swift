import Foundation

/// Animate → Layer effects → Bounce over the frames (0.165): the active layer hops a few times
/// across the existing frames, each hop lower than the one before (`decay`), and lands back on its
/// own position – a ball, a happy jump. Each hop is a parabola, so it hangs at the top and hits the
/// ground fast. Added to the existing position. Works on the play range if set. One undo step.
extension Studio {
    static func bounceHeight(_ t: Double, bounces: Int, decay: Double) -> Double {
        let n = max(1, bounces), p = min(max(t, 0), 1) * Double(n)
        let hop = min(Int(p), n - 1), u = p - Double(hop)
        return pow(decay, Double(hop)) * 4 * u * (1 - u)
    }

    @discardableResult func bounceLayer(height: Double, bounces: Int = 3, decay: Double = 0.55) -> Int {
        guard frames.count >= 2, height > 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.count >= 2 else { return 0 }
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let h = height * Studio.bounceHeight(Double(k) / Double(r.count - 1), bounces: bounces, decay: decay)
            guard h > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked { nf[i][j].transform.y -= h; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Bounce")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }

    /// Bounce with squash & stretch (0.180) as one undo step.
    @discardableResult func bounceWithSquash(height: Double, bounces: Int) -> Int {
        let n = bounceLayer(height: height, bounces: bounces)
        guard n > 0 else { return 0 }
        let before = undoStack.count
        squashStretch(amount: 1.4)
        if undoStack.count > before { undoStack.removeLast() }   // one step with the bounce
        return n
    }
}
