import Foundation

/// Animation → Layer effects → Wavy text → Letters fly apart (0.256): the exit to "Letters drop in" –
/// the text stays still for the first half, then every letter shoots off in its own direction (seeded,
/// mostly upwards and sideways), faster and faster, and fades out. Played over the play range (or all
/// frames). One undo step. Returns how many letters fly.
extension Studio {
    /// 0 until halfway, then 0…1 eased in (slow start, fast finish).
    static func scatterProgress(frame k: Int, frames n: Int) -> Double {
        guard n > 1 else { return 1 }
        let t = Double(k) / Double(n - 1), u = max(0, (t - 0.5) / 0.5)
        return u * u
    }

    @discardableResult func lettersScatter() -> Int {
        guard frames.count >= 2, let src = activeLayer, src.allFrames != true,
              src.strokes.contains(where: { $0.kind == "text" && !($0.text ?? "").isEmpty }) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let reach = Double(max(width, height))
        var nf = frames, letters = 0
        for (k, i) in r.enumerated() {
            let p = Studio.scatterProgress(frame: k, frames: r.count)
            for j in nf[i].indices where nf[i][j].id == src.id && !nf[i][j].locked {
                let split = nf[i][j].strokes.flatMap { $0.kind == "text" ? Studio.letterStrokes($0) : [$0] }
                let total = split.filter { $0.kind == "text" }.count
                let dirs = Studio.shakeOffsets(count: max(1, total), seed: 0x5CA7)
                var n = 0
                nf[i][j].strokes = split.map { part in
                    guard part.kind == "text" else { return part }
                    let d = dirs[n]
                    let dx = d.0, dy = -0.4 - abs(d.1) * 0.8                 // sideways, always a bit upwards
                    let len = max(0.01, (dx * dx + dy * dy).squareRoot())
                    var q = part
                    q.points[0].x += dx / len * reach * p
                    q.points[0].y += dy / len * reach * p
                    q.color.alpha *= 1 - min(1, p * 1.6)
                    n += 1; return q
                }
                if k == 0 { letters += total }
            }
        }
        guard letters > 0 else { return 0 }
        checkpoint("Letters fly apart")
        frames = nf; layers = frames[frameIndex]; changed()
        return letters
    }
}
