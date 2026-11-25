import Foundation

/// Animate → Layer motion → Mirror the motion (0.170): the active layer's path is mirrored around
/// where it starts – it goes left instead of right (or down instead of up), and its turning runs
/// the other way. The drawings are not flipped (that's Flip layer in all frames). Works on the
/// play range if set. One undo step. Returns how many frames changed.
extension Studio {
    @discardableResult func mirrorLayerMotion(horizontal: Bool) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let slots = r.compactMap { i in frames[i].firstIndex { $0.id == id }.map { (i, $0) } }
        guard let (fi, fj) = slots.first else { return 0 }
        let o = frames[fi][fj].transform
        var nf = frames, touched = 0
        for (i, j) in slots {
            var t = nf[i][j].transform
            if horizontal { t.x = 2 * o.x - t.x } else { t.y = 2 * o.y - t.y }
            t.rotation = 2 * o.rotation - t.rotation
            if nf[i][j].transform != t { nf[i][j].transform = t; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Mirror motion")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
