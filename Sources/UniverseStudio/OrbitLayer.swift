import Foundation

/// Animate → Layer effects → Orbit (0.164): the active layer runs on a circle that starts at its position, over
/// the existing frames, as a seamless loop – a fly, a planet, a leaf in the wind. `squash` < 1 makes
/// the circle an ellipse (a flatter, more "3D" orbit). Added to the existing position, so the frame
/// where the circle starts stays where it is. Works on the play range if set. One undo step.
/// `figureEight` (0.218) runs a lying 8 instead – a bee, a stunt plane, a dancing light.
extension Studio {
    static func orbitOffset(_ k: Int, of n: Int, radius: Double, clockwise: Bool, squash: Double) -> (Double, Double) {
        let a = 2 * Double.pi * Double(k) / Double(max(1, n)) * (clockwise ? 1 : -1)
        return (radius * sin(a), -radius * squash * (1 - cos(a)))   // starts at 0,0
    }

    /// A lying figure eight through the start point, one full 8 per loop.
    static func figureEightOffset(_ k: Int, of n: Int, radius: Double) -> (Double, Double) {
        let a = 2 * Double.pi * Double(k) / Double(max(1, n))
        return (radius * sin(a), radius * 0.45 * sin(2 * a))
    }

    @discardableResult func orbitLayer(radius: Double, clockwise: Bool = true, squash: Double = 1, figureEight: Bool = false) -> Int {
        guard frames.count >= 2, radius > 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let (dx, dy) = figureEight ? Studio.figureEightOffset(k, of: r.count, radius: radius)
                                       : Studio.orbitOffset(k, of: r.count, radius: radius, clockwise: clockwise, squash: squash)
            guard abs(dx) > 1e-9 || abs(dy) > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                nf[i][j].transform.x += dx; nf[i][j].transform.y += dy; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Orbit")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
