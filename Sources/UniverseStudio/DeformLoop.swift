import Foundation

/// Animation → Bend & wobble (0.115): the drawing on the active layer moves in itself as a
/// seamless loop – a wave runs through it, it sways like grass in the wind (the bottom stays), or it
/// squashes and stretches like jelly standing on the ground. Works on strokes, shapes and text
/// (their points move); pixel content stays as it is.
enum DeformLoop: String, CaseIterable, Identifiable {
    case wave, sway, jelly
    var id: String { rawValue }
    var title: String { switch self { case .wave: "Wave"; case .sway: "Sway"; case .jelly: "Squash & stretch" } }
    var symbol: String { switch self { case .wave: "water.waves"; case .sway: "wind"; case .jelly: "circle.and.line.horizontal" } }

    struct Box { var minX, minY, maxX, maxY: Double; var w: Double { maxX - minX }; var h: Double { maxY - minY } }

    static func box(_ strokes: [InkStroke]) -> Box? {
        let pts = strokes.filter { $0.imageData == nil }.flatMap(\.points)
        guard let f = pts.first else { return nil }
        return pts.reduce(Box(minX: f.x, minY: f.y, maxX: f.x, maxY: f.y)) { b, p in
            Box(minX: min(b.minX, p.x), minY: min(b.minY, p.y), maxX: max(b.maxX, p.x), maxY: max(b.maxY, p.y))
        }
    }

    /// Where point (x, y) goes at `t` (0…1 over the loop); `strength` 1 = normal.
    func move(_ x: Double, _ y: Double, t: Double, box b: Box, strength k: Double) -> (Double, Double) {
        let phase = 2 * Double.pi * t
        switch self {
        case .wave:
            let len = max(40, b.w / 1.5), a = max(2, b.h * 0.05) * k
            return (x, y + a * sin(2 * .pi * (x - b.minX) / len - phase))
        case .sway:
            let u = b.h > 0 ? (b.maxY - y) / b.h : 0      // 0 at the bottom, 1 at the top
            return (x + b.h * 0.12 * k * u * u * sin(phase), y)
        case .jelly:
            let s = 0.08 * k * sin(phase), cx = (b.minX + b.maxX) / 2
            return (cx + (x - cx) * (1 + s), b.maxY + (y - b.maxY) * (1 - s))
        }
    }

    func strokes(_ all: [InkStroke], t: Double, box b: Box, strength k: Double) -> [InkStroke] {
        all.map { s in
            guard s.imageData == nil else { return s }
            var m = s
            m.points = s.points.map { p in
                var q = p; (q.x, q.y) = move(p.x, p.y, t: t, box: b, strength: k); return q
            }
            return m
        }
    }
}

extension Studio {
    /// Replaces the current frame with `count` looping frames of the active layer bending.
    @discardableResult func deformLoop(_ d: DeformLoop, count: Int, strength: Double = 1) -> Int {
        guard count > 1, let layer = activeLayer, let box = DeformLoop.box(layer.strokes) else { return 0 }
        stopPlayback(); checkpoint("Bend & wobble")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let source = frames[frameIndex], id = layer.id
        let made: [[ArtLayer]] = (0..<count).map { k in
            source.map { l in
                guard l.id == id else { return l }
                var m = l; m.strokes = d.strokes(l.strokes, t: Double(k) / Double(count), box: box, strength: strength); return m
            }
        }
        frames[frameIndex] = made[0]
        metaInsert(at: frameIndex + 1, holds: Array(repeating: 1, count: made.count - 1))
        frames.insert(contentsOf: made.dropFirst(), at: frameIndex + 1)
        layers = frames[frameIndex]
        changed()
        return made.count
    }
}
