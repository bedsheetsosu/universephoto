import Foundation

/// Animate → Colour cycle → Rainbow over existing frames (0.137): turns the hue of the active
/// layer's strokes, shapes and text a little more in each frame, so the colour runs once around
/// the wheel across the whole animation – a seamless rainbow over time. Pixel content keeps its
/// colours. Works on the play range if one is set, otherwise all frames. One undo step; it stacks
/// if run again.
extension Studio {
    @discardableResult func rainbowAllFrames() -> Int {
        guard frames.count >= 2, let layer = activeLayer,
              layer.strokes.contains(where: { !$0.isEraser && $0.imageData == nil }) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let id = layer.id
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let n = r.count
        var nf = frames, changedAny = false
        for (k, i) in r.enumerated() {
            let turns = Double(k) / Double(n)
            guard turns != 0 else { continue }
            for j in nf[i].indices where nf[i][j].id == id {
                for si in nf[i][j].strokes.indices where !nf[i][j].strokes[si].isEraser && nf[i][j].strokes[si].imageData == nil {
                    nf[i][j].strokes[si].color = ColorCycle.rotate(nf[i][j].strokes[si].color, turns)
                    changedAny = true
                }
            }
        }
        guard changedAny else { return 0 }
        checkpoint("Rainbow over frames")
        frames = nf; layers = frames[frameIndex]; changed()
        return n
    }
}
