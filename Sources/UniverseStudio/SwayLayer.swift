import Foundation

/// Animate → Sway layer (0.140): rocks the active layer gently back and forth (rotation) across the
/// frames as a seamless loop – a swing, a wag, a bit of life. Completes the secondary-motion family
/// with Pulse layer (opacity), Float layer (position) and Pulse size (scale). It adds to the layer's
/// rotation per frame (undo to remove; running again stacks). Works on the play range if one is set,
/// otherwise all frames. One undo step. With `hanging` (0.204) it swings from the top of the drawing
/// like a pendulum – a lamp, a sign, a bell.
extension Studio {
    /// Rotation offset in degrees for frame `k` of `count`: a sine that returns to zero at the ends.
    static func swayDegrees(frameIndexInRange k: Int, count: Int, degrees: Double) -> Double {
        guard count >= 2 else { return 0 }
        return degrees * sin(2 * .pi * Double(k) / Double(count))
    }

    @discardableResult func swayLayer(degrees: Double, hanging: Bool = false) -> Int {
        guard frames.count >= 2, degrees != 0, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let n = r.count
        var nf = frames, changedAny = false
        for (k, i) in r.enumerated() {
            let off = Studio.swayDegrees(frameIndexInRange: k, count: n, degrees: degrees)
            guard abs(off) > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id {
                pivotEdit(&nf[i][j], hanging ? .top : .centre) { $0.rotation += off }
                changedAny = true
            }
        }
        guard changedAny else { return 0 }
        checkpoint("Sway layer")
        frames = nf; layers = frames[frameIndex]; changed()
        return n
    }
}
