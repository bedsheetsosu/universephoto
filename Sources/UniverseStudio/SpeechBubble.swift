import Foundation
import CoreText
import CoreGraphics

/// Animation → Effects → Speech bubble (0.261): a comic speech bubble pops up beside the active layer
/// with its tail pointing at it, then the text of the Text tool is typed into it letter by letter and
/// stays. (With the Text tool's default text it says "Hello!".) The bubble is sized for the whole text
/// from the start, follows the layer and stays inside the picture. On a new layer above it. Over the
/// play range (or all frames). One undo step. The shout bubble (0.262) is bigger, trembles, has red
/// letters and jagged strokes all around.
extension Studio {
    /// What the bubble says: the Text tool's text, or a friendly default.
    var speechBubbleText: String {
        let t = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "UniverseStudio" ? L("Hello!") : t
    }

    static func polygon(_ pts: [CGPoint], _ colour: CodableColor) -> InkStroke {
        var s = InkStroke(points: pts.flatMap { [InkPoint(x: $0.x, y: $0.y, pressure: 1), InkPoint(x: $0.x, y: $0.y, pressure: 1)] },
                          color: colour, width: 1)
        s.kind = "path"; s.pathClosed = true; s.filled = true
        return s
    }

    /// Strokes of the bubble at time `t` (0…1): `box` is the bubble at full size, `tip` where the tail points.
    static func speechBubbleStrokes(t: Double, text: String, fontSize: Double, textWidth: Double, box: CGRect, tip: CGPoint, shout: Bool = false) -> [InkStroke] {
        guard t > 0 else { return [] }
        let ink = CodableColor.black, paper = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
        let line = max(1.5, fontSize * 0.09), pop = t < 0.12 ? backOut(t / 0.12) : 1
        let b = CGRect(x: box.midX - box.width * pop / 2, y: box.midY - box.height * pop / 2, width: box.width * pop, height: box.height * pop)
        let near = tip.x < b.midX ? b.minX + b.width * 0.25 : b.maxX - b.width * 0.25
        let baseY = tip.y > b.midY ? b.maxY - line : b.minY + line
        let tailTip = CGPoint(x: b.midX + (tip.x - b.midX) * pop, y: b.midY + (tip.y - b.midY) * pop)
        let half = min(b.width, b.height) * 0.14
        let tail = [CGPoint(x: near - half, y: baseY), CGPoint(x: near + half, y: baseY), tailTip]
        func rounded(_ r: CGRect, _ c: CodableColor) -> InkStroke {
            var s = InkStroke(points: [InkPoint(x: r.minX, y: r.minY, pressure: 1), InkPoint(x: r.maxX, y: r.maxY, pressure: 1)], color: c, width: 1)
            s.kind = "roundedRect"; s.filled = true; s.strength = min(r.width, r.height) * 0.45
            return s
        }
        // Outline: the dark shapes a line wider, then the white ones on top (tail joins the bubble seamlessly).
        let grow = tail.map { p in CGPoint(x: p.x + (p.x - near) * 0.15, y: p.y + (p.y == tailTip.y ? (tip.y > b.midY ? line : -line) : 0)) }
        var out = [polygon(grow, ink), rounded(b.insetBy(dx: -line, dy: -line), ink), polygon(tail, paper), rounded(b, paper)]
        if t >= 0.15 {
            let shown = min(1, (t - 0.15) / 0.45), n = Int((Double(text.count) * shown).rounded(.up))
            // Left-aligned at the final position, so typing doesn't shift the letters already there.
            let rows = Double(text.components(separatedBy: .newlines).count)
            var s = InkStroke(points: [InkPoint(x: b.midX - textWidth / 2, y: b.midY - fontSize * 0.6 * rows - fontSize * 0.1, pressure: 1)],
                              color: shout ? CodableColor(red: 0.85, green: 0.1, blue: 0.12, alpha: 1) : ink, width: fontSize)
            s.kind = "text"; s.text = String(text.prefix(n)); s.fontName = "Helvetica-Bold"
            if !(s.text ?? "").isEmpty { out.append(s) }
        }
        if shout && pop >= 1 {
            // Shout (0.262): short jagged strokes all around the bubble, flickering in length.
            let flick = Int(t * 40) % 2 == 0 ? 1.0 : 0.75
            for k in 0..<14 {
                let a = Double(k) / 14 * 2 * .pi + 0.2
                let edge = CGPoint(x: b.midX + cos(a) * (b.width / 2 + line * 3), y: b.midY + sin(a) * (b.height / 2 + line * 3))
                let len = fontSize * (k % 2 == 0 ? 0.9 : 0.55) * flick
                out.append(InkStroke(points: [InkPoint(x: edge.x, y: edge.y, pressure: 1),
                                              InkPoint(x: edge.x + cos(a) * len, y: edge.y + sin(a) * len, pressure: 1)], color: ink, width: line * 1.2))
            }
        }
        return out
    }

    @discardableResult func addSpeechBubble(shout: Bool = false) -> Int {
        guard frames.count >= 2, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let w = Double(width), h = Double(height), text = speechBubbleText
        let size = min(40, max(12, min(w, h) * 0.065)) * (shout ? 1.2 : 1)
        var probe = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .black, width: size)
        probe.kind = "text"; probe.text = text; probe.fontName = "Helvetica-Bold"
        let lines = Renderer.textLines(probe, at: .zero)
        let textW = lines.map { CTLineGetTypographicBounds($0.line, nil, nil, nil) }.max() ?? size
        let bw = min(w * 0.9, textW + size * 2.2), bh = size * 1.2 * Double(max(1, lines.count)) + size * 1.0
        let shake = Studio.shakeOffsets(count: r.count, seed: 0x5407)
        checkpoint(shout ? "Shout bubble" : "Speech bubble")
        let layer = ArtLayer(name: L(shout ? "Shout bubble" : "Speech bubble"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let m = matrix(s.transform)
                let head = CGPoint(x: local.maxX - local.width * 0.2, y: local.minY + local.height * 0.1).applying(m)
                var c = CGPoint(x: head.x + bw * 0.45, y: head.y - bh * 1.1)
                c.x = min(max(c.x, bw / 2 + 4), w - bw / 2 - 4)
                c.y = min(max(c.y, bh / 2 + 4), h - bh / 2 - 4)
                if shout { c.x += shake[i - r.lowerBound].0 * size * 0.12; c.y += shake[i - r.lowerBound].1 * size * 0.12 }
                let box = CGRect(x: c.x - bw / 2, y: c.y - bh / 2, width: bw, height: bh)
                let t = r.count > 1 ? Double(i - r.lowerBound) / Double(r.count - 1) : 1
                l.strokes = Studio.speechBubbleStrokes(t: max(t, 0.001), text: text, fontSize: size, textWidth: textW, box: box, tip: head, shout: shout)
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return r.count
    }
}
