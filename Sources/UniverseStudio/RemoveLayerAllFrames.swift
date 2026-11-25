import Foundation

/// Animate → Remove layer from all frames (0.141): deletes the active layer from every frame at
/// once – handy for clearing a rotoscope or reference underlay you drew over, without visiting each
/// frame. A frame never loses its last layer (it is skipped). Works on the play range if one is set,
/// otherwise all frames. One undo step. Returns how many frames lost the layer.
extension Studio {
    @discardableResult func removeLayerFromAllFrames() -> Int {
        guard frames.count >= 1, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for i in r where nf[i].contains(where: { $0.id == id }) && nf[i].count > 1 {
            nf[i].removeAll { $0.id == id }
            touched += 1
        }
        guard touched > 0 else { return 0 }
        checkpoint("Remove layer from all frames")
        frames = nf
        layers = frames[frameIndex]
        selectedLayer = min(selectedLayer, layers.count - 1)
        selectedIDs = []
        changed()
        return touched
    }
}
