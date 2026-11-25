import Foundation

/// Animate → Layer effects → Breathe / Jelly (0.182), built on squash & stretch:
/// - Breathe: a calm stretch in and out as a seamless loop – an idle character, a sleeping cat.
/// - Jelly: a damped wobble that starts strong and settles – after a landing or a poke.
/// Multiplies onto the stretch each frame already has. Works on the play range if set. One undo step.
extension Studio {
    static func breatheStretch(_ k: Int, of n: Int, amount: Double) -> Double {
        1 + amount * sin(2 * .pi * Double(k) / Double(max(1, n)))
    }

    static func jellyStretch(_ k: Int, of n: Int, amount: Double) -> Double {
        guard n > 1 else { return 1 }
        let t = Double(k) / Double(n - 1)
        return 1 + amount * exp(-4 * t) * sin(t * .pi * 7)
    }

    @discardableResult func stretchEffect(jelly: Bool, amount: Double) -> Int {
        guard frames.count >= 2, amount > 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let f = jelly ? Studio.jellyStretch(k, of: r.count, amount: amount) : Studio.breatheStretch(k, of: r.count, amount: amount)
            guard abs(f - 1) > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                pivotEdit(&nf[i][j], .bottom) { $0.stretch = max(0.3, min(3, ($0.stretch ?? 1) * f)) }; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint(jelly ? "Jelly" : "Breathe")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
