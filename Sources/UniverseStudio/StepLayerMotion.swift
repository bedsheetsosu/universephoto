import Foundation

/// Animate → Layer motion → Step the motion (0.173): the active layer's position, size, turn and
/// opacity only change every 2nd or 3rd frame and hold in between – a choppy stop-motion or
/// "on twos" look for one layer while the rest stays smooth. Drawings stay as they are. Works on
/// the play range if set. One undo step. Returns how many frames changed.
extension Studio {
    @discardableResult func stepLayerMotion(every n: Int) -> Int {
        guard frames.count >= 2, n >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let slots = r.compactMap { i in frames[i].firstIndex { $0.id == id }.map { (i, $0) } }
        var nf = frames, touched = 0
        for (k, (i, j)) in slots.enumerated() where k % n != 0 {
            let (si, sj) = slots[k - k % n], src = frames[si][sj]
            if nf[i][j].transform != src.transform || nf[i][j].opacity != src.opacity {
                nf[i][j].transform = src.transform; nf[i][j].opacity = src.opacity; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Step motion")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
