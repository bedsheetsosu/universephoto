import Foundation

/// Animate → Pin layer state to all frames (0.146): copies the active layer's position, size, turn
/// and opacity from the current frame into every frame – to "un-animate" a layer or nail it to one
/// spot. The drawings stay as they are in each frame. Works on the play range if one is set,
/// otherwise all frames. One undo step. Returns how many frames changed.
extension Studio {
    @discardableResult func pinLayerStateToAllFrames() -> Int {
        guard frames.count >= 2, let source = activeLayer else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for i in r {
            for j in nf[i].indices where nf[i][j].id == source.id {
                if nf[i][j].transform != source.transform || nf[i][j].opacity != source.opacity {
                    nf[i][j].transform = source.transform; nf[i][j].opacity = source.opacity; touched += 1
                }
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Pin layer state")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
