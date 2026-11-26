import Foundation
import CoreGraphics

/// Animation → Effects → Thought bubble (0.259): the comic "thinking" bubble above the active layer –
/// two little bubbles rise one after another, then a cloud pops up in which "…" appears dot by dot
/// and keeps cycling. The cloud has one clean outline (dark ovals underneath, white ovals on top).
/// It follows the layer if it moves and stays inside the picture. On a new layer above it. Over the
/// play range (or all frames). One undo step.
extension Studio {
    static func oval(_ c: CGPoint, rx: Double, ry: Double, _ colour: CodableColor) -> InkStroke {
        var s = InkStroke(points: [InkPoint(x: c.x - rx, y: c.y - ry, pressure: 1), InkPoint(x: c.x + rx, y: c.y + ry, pressure: 1)],
                          color: colour, width: 1)
        s.kind = "ellipse"; s.filled = true
        return s
    }

    /// Strokes of the bubble at time `t` (0…1 of the range), cloud centre `c`, cloud radius `r`,
    /// small bubbles starting near `from`.
    static func thoughtBubbleStrokes(t: Double, from: CGPoint, cloud c: CGPoint, radius r: Double) -> [InkStroke] {
        let ink = CodableColor.black, paper = CodableColor(red: 1, green: 1, blue: 1, alpha: 1), line = max(1.5, r * 0.06)
        var out: [InkStroke] = []
        func outlined(_ p: CGPoint, _ rx: Double, _ ry: Double) -> (InkStroke, InkStroke) {
            (oval(p, rx: rx + line, ry: ry + line, ink), oval(p, rx: rx, ry: ry, paper))
        }
        // Two small bubbles on the way from the head to the cloud.
        for (n, at) in [(0, 0.06), (1, 0.14)] where t >= at {
            let f = 0.18 + 0.24 * Double(n)
            let p = CGPoint(x: from.x + (c.x - from.x) * f, y: from.y + (c.y - from.y) * f)
            let rr = r * (0.12 + 0.07 * Double(n)) * min(1, (t - at) / 0.04 + 0.4)
            let (a, b) = outlined(p, rr, rr); out += [a, b]
        }
        guard t >= 0.22 else { return out }
        let grow = min(1, (t - 0.22) / 0.06), pop = grow < 1 ? grow * 1.15 : 1
        let puffs: [(Double, Double, Double)] = [(-0.55, 0.05, 0.5), (0, -0.3, 0.55), (0.55, -0.05, 0.5), (0.25, 0.3, 0.45), (-0.25, 0.32, 0.45), (0, 0, 0.6)]
        let pts = puffs.map { (CGPoint(x: c.x + $0.0 * r * pop, y: c.y + $0.1 * r * 0.7 * pop), $0.2 * r * pop) }
        let pairs = pts.map { outlined($0.0, $0.1 * 1.1, $0.1 * 0.8) }
        out += pairs.map(\.0) + pairs.map(\.1)
        // "…": dots appear one by one from 0.32, then cycle 1-2-3.
        if t >= 0.32 {
            let step = Int((t - 0.32) / 0.08), dots = step % 3 + 1
            for d in 0..<dots {
                out.append(oval(CGPoint(x: c.x + (Double(d) - 1) * r * 0.32, y: c.y + r * 0.05), rx: r * 0.07, ry: r * 0.07, ink))
            }
        }
        return out
    }

    @discardableResult func addThoughtBubble() -> Int {
        guard frames.count >= 2, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let w = Double(width), h = Double(height)
        let radius = max(18, min(min(w, h) * 0.18, max(local.width, local.height) * 0.4))
        checkpoint("Thought bubble")
        let layer = ArtLayer(name: L("Thought bubble"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let m = matrix(s.transform)
                let head = CGPoint(x: local.maxX - local.width * 0.15, y: local.minY).applying(m)
                var c = CGPoint(x: head.x + radius * 0.9, y: head.y - radius * 1.5)
                c.x = min(max(c.x, radius * 1.3), w - radius * 1.3)
                c.y = min(max(c.y, radius * 0.95), h - radius * 0.95)
                let t = r.count > 1 ? Double(i - r.lowerBound) / Double(r.count - 1) : 1
                l.strokes = Studio.thoughtBubbleStrokes(t: t, from: head, cloud: c, radius: radius)
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return r.count
    }
}
