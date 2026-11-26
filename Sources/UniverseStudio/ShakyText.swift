import Foundation

/// Animation → Layer effects → Wavy text → Shaky letters (0.254): every letter of the text on the
/// active layer trembles on its own – for scared, freezing or angry words. Seeded per letter, so it
/// is the same every time. Text that is already split into letters (Wavy text) keeps one tremble
/// per letter. Works on the play range (or all frames). One undo step. Returns how many letters shake.
extension Studio {
    @discardableResult func shakyLetters(amount: Double = 0.06) -> Int {
        guard frames.count >= 2, amount > 0, let src = activeLayer, src.allFrames != true,
              src.strokes.contains(where: { $0.kind == "text" && !($0.text ?? "").isEmpty }) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, letters = 0
        var offsets: [Int: [(Double, Double, Double)]] = [:]
        for (k, i) in r.enumerated() {
            for j in nf[i].indices where nf[i][j].id == src.id && !nf[i][j].locked {
                let split = nf[i][j].strokes.flatMap { $0.kind == "text" ? Studio.letterStrokes($0) : [$0] }
                var n = 0
                nf[i][j].strokes = split.map { part in
                    guard part.kind == "text" else { return part }
                    let o = offsets[n] ?? Studio.shakeOffsets(count: r.count, seed: 0x5EED &+ UInt64(n + 1) &* 7919)
                    offsets[n] = o
                    let a = max(1, part.width * amount)
                    var q = part
                    q.points[0].x += o[k].0 * a; q.points[0].y += o[k].1 * a
                    n += 1; return q
                }
                if k == 0 { letters += n }
            }
        }
        guard letters > 0 else { return 0 }
        checkpoint("Shaky letters")
        frames = nf; layers = frames[frameIndex]; changed()
        return letters
    }
}
