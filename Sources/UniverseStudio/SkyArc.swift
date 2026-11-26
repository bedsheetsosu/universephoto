import Foundation

/// Animation → Layer effects → Arc across the sky (0.289): the active layer travels in a high arch
/// from the left edge of the picture to the right – a sun or moon crossing the sky, a thrown ball, a
/// jumping dolphin. It starts and ends at its own height, offset half a picture to each side, and
/// peaks in the middle. Over the play range (or all frames). Adds onto the motion. One undo step.
extension Studio {
    /// Offset at progress `t` (0…1) for a picture `w` × `h`: left to right, up in the middle.
    static func skyArc(_ t: Double, width w: Double, height h: Double, rise: Double) -> (dx: Double, dy: Double) {
        (w * (t - 0.5), -h * rise * sin(.pi * t))
    }

    @discardableResult func skyArcLayer(rise: Double = 0.4) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.count >= 2 else { return 0 }
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let o = Studio.skyArc(Double(k) / Double(r.count - 1), width: Double(width), height: Double(height), rise: rise)
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                nf[i][j].transform.x += o.dx; nf[i][j].transform.y += o.dy; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Arc across the sky")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
