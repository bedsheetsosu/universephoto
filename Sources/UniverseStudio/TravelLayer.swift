import Foundation

/// Animate → Layer effects → Travel over the frames (0.162): the active layer moves a set distance
/// across the existing frames – e.g. a car crossing the whole canvas – linearly or with a soft start
/// and stop. The movement is added to what each frame already has, so a walk cycle keeps walking
/// while it travels. Works on the play range if one is set, otherwise all frames. One undo step.
extension Studio {
    @discardableResult func travelLayer(dx: Double, dy: Double, eased: Bool) -> Int {
        guard frames.count >= 2, dx != 0 || dy != 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.count >= 2 else { return 0 }
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let t = Double(k) / Double(r.count - 1)
            let f = eased ? Studio.fadeRamp(k, of: r.count, fadeIn: true) : t
            guard f != 0 else { continue }
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                nf[i][j].transform.x += dx * f; nf[i][j].transform.y += dy * f; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Travel")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
