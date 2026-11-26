import Foundation
import CoreGraphics

/// Animation → Layer effects → Rise up (0.220): the active layer rises out of the ground at its own
/// bottom edge – as if it came up from behind a wall, a counter or the edge of a hole – or sinks back
/// down into it. The part below that line is hidden with the layer mask, so nothing pokes out under
/// the "floor". Soft ease, over the play range (or all frames). One undo step.
extension Studio {
    @discardableResult func riseUp(sink: Bool = false) -> Int {
        guard frames.count >= 2, let src = activeLayer, src.allFrames != true, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let shown = Studio.fadeRamp(k, of: r.count, fadeIn: !sink)      // 0 = all below the line
            guard shown < 1 - 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == src.id && !nf[i][j].locked {
                let box = local.applying(matrix(nf[i][j].transform))
                let floor = box.maxY                                     // the line stays where the feet were
                nf[i][j].transform.y += box.height * (1 - shown)
                // Hide everything of the layer that is now below the floor (in layer coordinates).
                let inv = matrix(nf[i][j].transform).inverted()
                let a = CGPoint(x: box.minX - box.width, y: floor).applying(inv), b = CGPoint(x: box.maxX + box.width, y: floor).applying(inv)
                let cut = min(a.y, b.y)
                var cover = InkStroke(points: [InkPoint(x: local.minX - local.width * 2, y: cut, pressure: 1),
                                               InkPoint(x: local.maxX + local.width * 2, y: local.maxY + local.height * 3 + 10, pressure: 1)], color: .maskBlack, width: 1)
                cover.kind = "rectangle"; cover.filled = true
                nf[i][j].mask = (nf[i][j].mask ?? []) + [cover]
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint(sink ? "Sink down" : "Rise up")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
