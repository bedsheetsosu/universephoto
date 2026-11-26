import Foundation
import CoreGraphics
import CoreText

/// Animation → Layer effects → Wavy text (0.251): the letters of the text on the active layer move
/// one by one – a wave running through them, or each letter hopping in turn. Each text box is split
/// into single letters at exactly the places they had (alignment and letter spacing kept), and every
/// letter gets its own offset per frame. A seamless loop over the play range (or all frames). One
/// undo step. Returns how many letters move.
extension Studio {
    /// The text stroke as one stroke per visible letter, each at its own place (left-aligned).
    static func letterStrokes(_ stroke: InkStroke) -> [InkStroke] {
        guard stroke.kind == "text", let text = stroke.text, !text.isEmpty, let p = stroke.points.first else { return [stroke] }
        let size = max(6, stroke.width), rows = text.components(separatedBy: .newlines)
        let lines = Renderer.textLines(stroke, at: CGPoint(x: p.x, y: p.y))
        var out: [InkStroke] = []
        for (r, row) in rows.enumerated() where r < lines.count {
            let line = lines[r], ns = row as NSString
            var idx = 0
            for ch in row {
                let len = String(ch).utf16.count
                defer { idx += len }
                if ch.isWhitespace { continue }
                let x = line.x + Double(CTLineGetOffsetForStringIndex(line.line, idx, nil))
                var l = stroke
                l.text = ns.substring(with: NSRange(location: idx, length: len))
                l.textAlign = nil; l.tracking = nil; l.lineSpacing = nil
                l.points = [InkPoint(x: x, y: line.baseline - size, pressure: 1)]
                out.append(l)
            }
        }
        return out.isEmpty ? [stroke] : out
    }

    /// Upward offset of letter `i` of `count` in frame `k` of `n`: a travelling wave, or hops in turn.
    static func letterLift(_ i: Int, of count: Int, frame k: Int, frames n: Int, height: Double, hop: Bool) -> Double {
        guard n > 0, count > 0 else { return 0 }
        let t = Double(k) / Double(n)
        if hop {
            let slot = Double(i) / Double(count), d = t - slot - (t - slot).rounded(.down)   // time since its turn
            let w = min(0.5, 2 / Double(count) + 0.1)
            return d < w ? height * sin(.pi * d / w) : 0
        }
        return height * 0.5 * (1 - cos(2 * .pi * (t * 2 - Double(i) * 0.12)))
    }

    /// Rainbow letters (0.252): each letter its own colour of the rainbow, the colours running along
    /// the text over the frames – a seamless loop. Starts from pure red at full brightness, so it also
    /// works on black or grey text.
    static func rainbowColour(_ i: Int, of count: Int, frame k: Int, frames n: Int, alpha: Double) -> CodableColor {
        let turn = Double(i) / Double(max(1, count)) - Double(k) / Double(max(1, n))
        return ColorCycle.rotate(CodableColor(red: 1, green: 0.25, blue: 0.25, alpha: alpha), turn)
    }

    @discardableResult func rainbowLetters() -> Int {
        guard frames.count >= 2, let src = activeLayer, src.allFrames != true,
              src.strokes.contains(where: { $0.kind == "text" && !($0.text ?? "").isEmpty }) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, letters = 0
        for (k, i) in r.enumerated() {
            for j in nf[i].indices where nf[i][j].id == src.id && !nf[i][j].locked {
                nf[i][j].strokes = nf[i][j].strokes.flatMap { s -> [InkStroke] in
                    guard s.kind == "text" else { return [s] }
                    let parts = Studio.letterStrokes(s)
                    if k == 0 { letters += parts.count }
                    return parts.enumerated().map { n, part in
                        var q = part; q.color = Studio.rainbowColour(n, of: parts.count, frame: k, frames: r.count, alpha: part.color.alpha)
                        return q
                    }
                }
            }
        }
        guard letters > 0 else { return 0 }
        checkpoint("Rainbow letters")
        frames = nf; layers = frames[frameIndex]; changed()
        return letters
    }

    @discardableResult func wavyText(hop: Bool) -> Int {
        guard frames.count >= 2, let src = activeLayer, src.allFrames != true,
              src.strokes.contains(where: { $0.kind == "text" && !($0.text ?? "").isEmpty }) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, letters = 0
        for (k, i) in r.enumerated() {
            for j in nf[i].indices where nf[i][j].id == src.id && !nf[i][j].locked {
                var split: [InkStroke] = []
                for s in nf[i][j].strokes {
                    guard s.kind == "text" else { split.append(s); continue }
                    let parts = Studio.letterStrokes(s), h = max(3, s.width * 0.35)
                    split += parts.enumerated().map { n, part in
                        var q = part
                        q.points[0].y -= Studio.letterLift(n, of: parts.count, frame: k, frames: r.count, height: h, hop: hop)
                        return q
                    }
                    if k == 0 { letters += parts.count }
                }
                nf[i][j].strokes = split
            }
        }
        guard letters > 0 else { return 0 }
        checkpoint("Wavy text")
        frames = nf; layers = frames[frameIndex]; changed()
        return letters
    }
}
