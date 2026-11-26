import Foundation

/// Animation → Layer effects → Wavy text → Letters drop in (0.255): the letters of the text on the
/// active layer fall in from above one after another and bounce to rest – a title entrance. Before
/// its turn a letter is invisible. Played over the play range (or all frames); after the last letter
/// lands the text stays still. One undo step. Returns how many letters drop.
extension Studio {
    /// Bounce-out easing 0…1 → 0…1 (lands, two small rebounds).
    static func bounceOut(_ t: Double) -> Double {
        let t = min(1, max(0, t)), n = 7.5625, d = 2.75
        if t < 1 / d { return n * t * t }
        if t < 2 / d { let u = t - 1.5 / d; return n * u * u + 0.75 }
        if t < 2.5 / d { let u = t - 2.25 / d; return n * u * u + 0.9375 }
        let u = t - 2.625 / d; return n * u * u + 0.984375
    }

    /// Fall progress of letter `i` of `count` at frame `k` of `n`: nil = not yet visible, 0…1 = falling/landed.
    static func dropProgress(_ i: Int, of count: Int, frame k: Int, frames n: Int) -> Double? {
        guard n > 1, count > 0 else { return 1 }
        let t = Double(k) / Double(n - 1)                      // last frame: everything landed
        let fall = 0.3, start = count > 1 ? Double(i) / Double(count - 1) * (0.7 - fall * 0.3) : 0
        if t < start { return nil }
        return min(1, (t - start) / fall)
    }

    @discardableResult func lettersDropIn() -> Int {
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
                        let lift = (q.points[0].y + q.width * 1.5) * (1 - Studio.bounceOut(p))   // from just above the top
                        q.points[0].y -= lift
                    } else {
                        q.color.alpha = 0
                    }
                    n += 1; return q
                }
                if k == 0 { letters += total }
            }
        }
        guard letters > 0 else { return 0 }
        checkpoint("Letters drop in")
        frames = nf; layers = frames[frameIndex]; changed()
        return letters
    }
}
