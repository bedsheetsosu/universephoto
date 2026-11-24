import Foundation

/// Animation → Draw on (0.104): the drawing on the active layer draws itself over new frames –
/// stroke by stroke, or smoothly along the line as if the pen were moving – then stays for a
/// moment. Brush strokes and lines grow; other shapes appear once the pen reaches them; text and
/// placed images are there from the start.
enum DrawOn {
    static func drawable(_ s: InkStroke) -> Bool { s.imageData == nil && s.kind != "text" && !s.points.isEmpty }
    static func grows(_ s: InkStroke) -> Bool { s.kind == nil || s.kind == "line" }

    static func length(_ p: [InkPoint]) -> Double {
        guard p.count > 1 else { return 0 }
        return (1..<p.count).reduce(0) { $0 + hypot(p[$1].x - p[$1 - 1].x, p[$1].y - p[$1 - 1].y) }
    }

    /// The first `d` units of the polyline (the last point cut in between).
    static func prefix(_ p: [InkPoint], _ d: Double) -> [InkPoint] {
        guard p.count > 1, d > 0 else { return Array(p.prefix(1)) }
        var out = [p[0]], run = 0.0
        for i in 1..<p.count {
            let seg = hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y)
            if run + seg >= d { out.append(StrokeMorph.mix(p[i - 1], p[i], seg > 0 ? (d - run) / seg : 1)); return out }
            run += seg; out.append(p[i])
        }
        return out
    }

    /// The strokes visible at step `k` of `n`. `byStroke`: whole strokes one after another;
    /// otherwise the pen travels the total length evenly (short shapes count a little, so they
    /// get a beat of their own).
    static func strokes(_ all: [InkStroke], step k: Int, of n: Int, byStroke: Bool) -> [InkStroke] {
        let idx = all.indices.filter { drawable(all[$0]) }
        if byStroke {
            let shown = Set(idx.prefix(Int((Double(idx.count) * Double(k) / Double(n)).rounded(.up))))
            return all.indices.filter { !drawable(all[$0]) || shown.contains($0) }.map { all[$0] }
        }
        let lens = idx.map { max(length(all[$0].points), 1) }, total = lens.reduce(0, +)
        let d = total * Double(k) / Double(n)
        var out: [InkStroke] = [], run = 0.0, j = 0
        for s in all {
            guard drawable(s) else { out.append(s); continue }
            let len = lens[j]; j += 1
            defer { run += len }
            if run + len <= d + 1e-9 { out.append(s); continue }
            guard run < d else { continue }
            if grows(s) { var t = s; t.points = prefix(s.points, (d - run) / len * length(s.points)); if t.points.count > 1 { out.append(t) } }
        }
        return out
    }
}

extension Studio {
    /// Replaces the current frame with `count` frames of the drawing appearing (the finished
    /// drawing is held for `restTicks`). Returns the number of frames, 0 when there's nothing.
    @discardableResult func drawOn(count: Int, byStroke: Bool, restTicks: Int = 12) -> Int {
        guard let layer = activeLayer else { return 0 }
        let n = layer.strokes.filter(DrawOn.drawable).count
        guard n > 0 else { return 0 }
        let steps = byStroke ? n : max(2, count)
        guard steps > 1 else { return 0 }
        stopPlayback(); checkpoint("Draw on")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let source = frames[frameIndex], id = layer.id
        let made: [[ArtLayer]] = (1...steps).map { k in
            source.map { l in
                guard l.id == id else { return l }
                var m = l; m.strokes = DrawOn.strokes(l.strokes, step: k, of: steps, byStroke: byStroke); return m
            }
        }
        frames[frameIndex] = made[0]
        metaInsert(at: frameIndex + 1, holds: Array(repeating: 1, count: made.count - 2) + [max(1, restTicks)])
        frames.insert(contentsOf: made.dropFirst(), at: frameIndex + 1)
        layers = frames[frameIndex]
        changed()
        return made.count
    }
}
