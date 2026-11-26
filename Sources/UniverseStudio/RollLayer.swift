import Foundation

/// Animation → Layer effects → Roll (0.284): the active layer rolls along the ground – a ball, a
/// wheel, a rolling barrel. It travels sideways with a gentle start and stop, and turns exactly as
/// much as a round thing of its size would over that distance, so it never slides. Works on the play
/// range (or all frames). Adds onto the motion already there. One undo step.
extension Studio {
    /// Degrees a wheel of `radius` turns when rolling `distance` (positive = to the right, clockwise).
    static func rollDegrees(distance: Double, radius: Double) -> Double {
        radius > 0 ? distance / radius * 180 / .pi : 0
    }

    @discardableResult func rollLayer(distance: Double) -> Int {
        guard frames.count >= 2, distance != 0, let src = activeLayer, src.allFrames != true, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.count >= 2 else { return 0 }
        let radius = max(1, max(local.width, local.height) / 2)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let t = Double(k) / Double(r.count - 1), f = t * t * (3 - 2 * t)
            let d = distance * f
            for j in nf[i].indices where nf[i][j].id == src.id && !nf[i][j].locked {
                let turn = Studio.rollDegrees(distance: d, radius: radius * nf[i][j].transform.scale)
                pivotEdit(&nf[i][j], .centre) { $0.rotation += turn }
                nf[i][j].transform.x += d
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Roll")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
