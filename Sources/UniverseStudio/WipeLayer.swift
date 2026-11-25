import Foundation

/// Animate → Layer effects → Wipe (0.176): the active layer is revealed (or wiped away) from one
/// side across the existing frames, with a soft ease – a title sliding into view behind an edge, a
/// line of paint, a curtain. Done with the layer mask: each frame gets a black, filled rectangle
/// over the part still hidden, on top of any mask it already has, so it stays editable and undoes
/// in one step. Works on the play range if set. Returns how many frames changed.
extension Studio {
    enum WipeDirection: String, CaseIterable, Identifiable {
        case leftToRight, rightToLeft, topToBottom, bottomToTop
        var id: String { rawValue }
        var title: String { switch self {
            case .leftToRight: "From the left"; case .rightToLeft: "From the right"
            case .topToBottom: "From the top"; case .bottomToTop: "From the bottom" } }
    }

    /// The hidden part at progress `p` (0 = all hidden for a reveal), as two corner points; nil = nothing hidden.
    static func wipeHidden(_ d: WipeDirection, progress p: Double, reveal: Bool, width w: Double, height h: Double) -> (InkPoint, InkPoint)? {
        let q = reveal ? p : 1 - p                 // share that is visible
        if q >= 1 { return nil }
        let x0 = -w, x1 = 2 * w, y0 = -h, y1 = 2 * h
        switch d {
        case .leftToRight: return (InkPoint(x: q * w, y: y0, pressure: 1), InkPoint(x: x1, y: y1, pressure: 1))
        case .rightToLeft: return (InkPoint(x: x0, y: y0, pressure: 1), InkPoint(x: (1 - q) * w, y: y1, pressure: 1))
        case .topToBottom: return (InkPoint(x: x0, y: q * h, pressure: 1), InkPoint(x: x1, y: y1, pressure: 1))
        case .bottomToTop: return (InkPoint(x: x0, y: y0, pressure: 1), InkPoint(x: x1, y: (1 - q) * h, pressure: 1))
        }
    }

    @discardableResult func wipeLayer(_ d: WipeDirection, reveal: Bool) -> Int {
        guard frames.count >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let p = Studio.fadeRamp(k, of: r.count, fadeIn: true)
            guard let (a, b) = Studio.wipeHidden(d, progress: p, reveal: reveal, width: Double(width), height: Double(height)) else { continue }
            var cover = InkStroke(points: [a, b], color: .black, width: 1)
            cover.kind = "rectangle"; cover.filled = true
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                nf[i][j].mask = (nf[i][j].mask ?? []) + [cover]; touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint(reveal ? "Wipe in" : "Wipe out")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
