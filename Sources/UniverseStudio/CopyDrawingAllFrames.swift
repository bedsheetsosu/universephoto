import Foundation

/// Animate → Layer motion → Copy drawing to all frames (0.166): the counterpart to Pin layer state.
/// The active layer's drawing (strokes, pixels and mask) from this frame goes into every frame,
/// while each frame keeps its own position, size, turn and opacity – draw a character once, then
/// animate it with the layer effects. Unlike "Same in all frames" the copies stay separate, so a
/// single frame can still be redrawn. Works on the play range if set. One undo step.
extension Studio {
    @discardableResult func copyDrawingToAllFrames() -> Int {
        guard frames.count >= 2, let src = activeLayer else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for i in r {
            if let j = nf[i].firstIndex(where: { $0.id == src.id }) {
                var l = nf[i][j]
                guard l.strokes != src.strokes || l.imageData != src.imageData || l.mask != src.mask else { continue }
                l.strokes = src.strokes; l.imageData = src.imageData; l.mask = src.mask
                nf[i][j] = l; touched += 1
            } else {
                // The layer is missing in this frame: add it at the same place in the stack.
                let at = min(selectedLayer, nf[i].count)
                nf[i].insert(src, at: at); touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Copy drawing")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
