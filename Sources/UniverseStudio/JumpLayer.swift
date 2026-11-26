import Foundation

/// Animation → Layer effects → Jump (0.227): one proper cartoon jump in place – the active layer
/// crouches (squashes) to wind up, shoots up stretched, hangs at the top, falls and lands squashed,
/// then springs back to normal. Squashes on its bottom edge so it stays on the ground. Over the play
/// range (or all frames). One undo step. Returns how many frames changed.
extension Studio {
    /// Lift (up, as a share of `height`) and stretch for frame `k` of `n`.
    static func jumpPose(_ k: Int, of n: Int) -> (lift: Double, stretch: Double) {
        guard n >= 2 else { return (0, 1) }
        let t = Double(k) / Double(n - 1)
        switch t {
        case ..<0.2:                                     // wind-up: crouch
            let c = sin(.pi * t / 0.2 * 0.5); return (0, 1 - 0.22 * c)
        case ..<0.7:                                     // flight: a parabola, stretched going up and down
            let u = (t - 0.2) / 0.5, lift = 4 * u * (1 - u)
            return (lift, 1 + 0.18 * abs(1 - 2 * u))
        case ..<0.85:                                    // landing: squash and come back up
            let u = (t - 0.7) / 0.15; return (0, 1 - 0.25 * sin(.pi * u))
        default:                                         // a small overshoot, then rest
            let u = (t - 0.85) / 0.15; return (0, 1 + 0.06 * sin(.pi * u))
        }
    }

    @discardableResult func jumpLayer(height: Double) -> Int {
        guard frames.count >= 4, height > 0, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let p = Studio.jumpPose(k, of: r.count)
            guard p.lift > 1e-9 || abs(p.stretch - 1) > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                pivotEdit(&nf[i][j], .bottom) { $0.stretch = ($0.stretch ?? 1) * p.stretch }
                nf[i][j].transform.y -= p.lift * height
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Jump")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
