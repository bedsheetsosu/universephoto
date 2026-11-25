import Foundation

/// Animate → Layer effects → Wipe → Circle (0.177): an iris – the active layer appears from a
/// growing circle in the middle of the canvas, or closes into a shrinking one, the classic cartoon
/// ending. Like Wipe it uses the layer mask (black over everything, a white circle on top) and
/// adds on top of the existing mask. Works on the play range if set. One undo step.
extension Studio {
    /// Radius at progress `p` for a `width` × `height` canvas; reaches the corners at full size.
    static func irisRadius(progress p: Double, open: Bool, width w: Double, height h: Double) -> Double {
        let full = (w * w + h * h).squareRoot() / 2
        return full * (open ? p : 1 - p)
    }

    @discardableResult func irisLayer(open: Bool) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let w = Double(width), h = Double(height), cx = w / 2, cy = h / 2
        let full = (w * w + h * h).squareRoot() / 2
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let rad = Studio.irisRadius(progress: Studio.fadeRamp(k, of: r.count, fadeIn: true), open: open, width: w, height: h)
            guard rad < full - 1e-9 else { continue }
            var black = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .black, width: 1); black.kind = "fill"
            var hole = InkStroke(points: [InkPoint(x: cx - rad, y: cy - rad, pressure: 1), InkPoint(x: cx + rad, y: cy + rad, pressure: 1)], color: .white, width: 1)
            hole.kind = "ellipse"; hole.filled = true
            let add = rad > 1e-9 ? [black, hole] : [black]
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                nf[i][j].mask = (nf[i][j].mask ?? []) + add; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint(open ? "Iris open" : "Iris close")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
