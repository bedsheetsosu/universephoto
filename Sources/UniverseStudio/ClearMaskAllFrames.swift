import Foundation

/// Animate → Layer effects → Wipe → Remove mask in all frames (0.178): takes the mask off the
/// active layer in every frame – to start a Wipe or Iris over, or to drop an old cut-out. Works on
/// the play range if set. One undo step. Returns how many frames changed.
extension Studio {
    @discardableResult func clearMaskAllFrames() -> Int {
        guard !frames.isEmpty, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for i in r { for j in nf[i].indices where nf[i][j].id == id && nf[i][j].mask != nil { nf[i][j].mask = nil; touched += 1 } }
        guard touched > 0 else { return 0 }
        checkpoint("Remove mask in all frames")
        maskEditing = false
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
