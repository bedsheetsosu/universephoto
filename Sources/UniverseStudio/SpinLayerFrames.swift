import Foundation

/// Animate → Layer across frames → Spin over the frames (0.157): the active layer turns full
/// circles across the existing frames (or the play range), evenly, as a seamless loop – the last
/// frame stops one step short of the first. Adds to the turn each frame already has. Unlike the
/// Spin motion preset, no frames are added. One undo step. Returns how many frames changed.
extension Studio {
    @discardableResult func spinLayerOverFrames(turns: Double) -> Int {
        guard frames.count >= 2, turns != 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let add = 360 * turns * Double(k) / Double(r.count)
            guard add != 0 else { continue }
            for j in nf[i].indices where nf[i][j].id == id { pivotEdit(&nf[i][j], .centre) { $0.rotation += add }; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Spin layer")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
