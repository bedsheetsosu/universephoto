import Foundation

/// Animate → Layer across frames → Shift in all frames (0.150): moves the active layer by the same
/// offset in every frame, so a finished movement can be placed elsewhere on the canvas without
/// losing it – unlike Pin layer state, which flattens the motion. Works on the play range if one is
/// set, otherwise all frames. One undo step. Returns how many frames changed.
extension Studio {
    @discardableResult func shiftLayerAllFrames(dx: Double, dy: Double) -> Int {
        guard frames.count >= 2, dx != 0 || dy != 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for i in r {
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                nf[i][j].transform.x += dx; nf[i][j].transform.y += dy; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Shift layer in all frames")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
