import Foundation

/// Animation → Layer effects → Wavy text → Letters pop in (0.258): the letters of the text on the
/// active layer grow out of nothing one after another, overshoot a little and settle – each around its
/// own middle, standing on the baseline. Before its turn a letter is invisible. Played over the play
/// range (or all frames); afterwards the text stays still. One undo step. Returns how many letters pop.
extension Studio {
    /// Ease-out with overshoot (back easing): 0 → ~1.1 → 1.
    static func backOut(_ t: Double) -> Double {
        let t = min(1, max(0, t)), c = 1.70158, u = t - 1
        return 1 + (c + 1) * u * u * u + c * u * u
    }

    @discardableResult func lettersPopIn() -> Int {
        guard frames.count >= 2, let src = activeLayer, src.allFrames != true,
              src.strokes.contains(where: { $0.kind == "text" && !($0.text ?? "").isEmpty }) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, letters = 0
        for (k, i) in r.enumerated() {
            for j in nf[i].indices where nf[i][j].id == src.id && !nf[i][j].locked {
                let split = nf[i][j].strokes.flatMap { $0.kind == "text" ? Studio.letterStrokes($0) : [$0] }
                let total = split.filter { $0.kind == "text" }.count
                var n = 0
                nf[i][j].strokes = split.map { part in
                    guard part.kind == "text" else { return part }
                    var q = part
                    if let p = Studio.dropProgress(n, of: total, frame: k, frames: r.count) {
                        let sc = p >= 1 ? 1 : Studio.backOut(p)
                        let size = max(6, part.width), half = size * 0.3        // about half a letter's width
                        q.width = max(0.5, size * sc)
                        q.points[0].x += half * (1 - sc)
                        q.points[0].y += size * (1 - sc)                          // keep it on the baseline
                        if sc < 0.25 { q.color.alpha *= max(0, sc / 0.25) }
                    } else {
                        q.color.alpha = 0
                    }
                    n += 1; return q
                }
                if k == 0 { letters += total }
            }
        }
        guard letters > 0 else { return 0 }
        checkpoint("Letters pop in")
        frames = nf; layers = frames[frameIndex]; changed()
        return letters
    }
}
