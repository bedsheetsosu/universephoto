import Foundation
import CoreGraphics

/// Animate → Layer effects → Wipe → Circle (0.177): an iris – the active layer appears from a
/// growing circle in the middle of the canvas, or closes into a shrinking one, the classic cartoon
/// ending (or a heart, 0.292). Like Wipe it uses the layer mask (black over everything, a white circle on top) and
/// adds on top of the existing mask. Works on the play range if set. One undo step.
extension Studio {
    /// Radius at progress `p` for a `width` × `height` canvas; reaches the corners at full size.
    static func irisRadius(progress p: Double, open: Bool, width w: Double, height h: Double) -> Double {
        let full = (w * w + h * h).squareRoot() / 2
        return full * (open ? p : 1 - p)
    }

    /// Outline of a heart around (`cx`, `cy`), `factor` × `rad` / 12 per heart unit (0.292).
    static func heartOutline(cx: Double, cy: Double, rad: Double, factor: Double = 2) -> [CGPoint] {
        let s = rad * factor / 12
        return (0..<64).map { k in
            let t = Double(k) / 64 * 2 * .pi
            let x = 16 * pow(sin(t), 3), y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
            return CGPoint(x: cx + x * s, y: cy + (y + 2.5) * s)
        }
    }

    /// Smallest heart factor whose full-size heart covers the whole `w` × `h` canvas (corners and the
    /// top middle, where the heart's notch is).
    static func heartCoverFactor(width w: Double, height h: Double) -> Double {
        let full = (w * w + h * h).squareRoot() / 2
        let probes = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), CGPoint(x: w, y: h), CGPoint(x: w / 2, y: 0), CGPoint(x: w / 2, y: h)]
        var f = 2.0
        while f < 12 {
            let path = CGMutablePath(); path.addLines(between: heartOutline(cx: w / 2, cy: h / 2, rad: full, factor: f)); path.closeSubpath()
            if probes.allSatisfy({ path.contains($0) }) { return f }
            f += 0.2
        }
        return f
    }

    @discardableResult func irisLayer(open: Bool, heart: Bool = false) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let w = Double(width), h = Double(height), cx = w / 2, cy = h / 2
        let full = (w * w + h * h).squareRoot() / 2
        let heartFactor = heart ? Studio.heartCoverFactor(width: w, height: h) : 2
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let rad = Studio.irisRadius(progress: Studio.fadeRamp(k, of: r.count, fadeIn: true), open: open, width: w, height: h)
            guard rad < full - 1e-9 else { continue }
            var black = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .maskBlack, width: 1); black.kind = "fill"
            var hole = InkStroke(points: [InkPoint(x: cx - rad, y: cy - rad, pressure: 1), InkPoint(x: cx + rad, y: cy + rad, pressure: 1)], color: .white, width: 1)
            hole.kind = "ellipse"; hole.filled = true
            // The full-size heart is far bigger than the picture, so it shrinks on a curve – it stays
            // visible for longer instead of rushing through the last frames.
            if heart { hole = Studio.polygon(Studio.heartOutline(cx: cx, cy: cy, rad: rad * rad / full, factor: heartFactor), .white) }
            let add = rad > 1e-9 ? [black, hole] : [black]
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                nf[i][j].mask = (nf[i][j].mask ?? []) + add; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint(heart ? (open ? "Heart open" : "Heart close") : open ? "Iris open" : "Iris close")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
