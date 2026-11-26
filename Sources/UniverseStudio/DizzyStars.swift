import Foundation
import CoreGraphics

/// Animation → Effects → Dizzy stars (0.264): a ring of little yellow stars circles above the active
/// layer – the cartoon "seeing stars" after a knock. The ring is tilted: stars at the back are smaller
/// and darker, at the front bigger. Two rounds over the play range (or all frames), a seamless loop,
/// following the layer. On a new layer above it. One undo step.
extension Studio {
    /// Centre, size factor (0.7 back … 1 front) and opacity of star `i` of `count` at time `t` (0…1).
    static func dizzyStar(_ i: Int, of count: Int, t: Double, centre c: CGPoint, radius r: Double) -> (CGPoint, Double, Double) {
        let a = 2 * .pi * (t * 2 + Double(i) / Double(max(1, count)))
        let depth = (sin(a) + 1) / 2                                     // 0 back, 1 front
        return (CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.28), 0.7 + 0.3 * depth, 0.55 + 0.45 * depth)
    }

    static func starStrokes(at p: CGPoint, size: Double, alpha: Double) -> [InkStroke] {
        func star(_ s: Double, _ colour: CodableColor) -> InkStroke {
            var k = InkStroke(points: [InkPoint(x: p.x - s, y: p.y - s, pressure: 1), InkPoint(x: p.x + s, y: p.y + s, pressure: 1)], color: colour, width: 1)
            k.kind = "star"; k.filled = true; k.strength = 5
            return k
        }
        // `alpha` here is brightness: the back stars are a deeper yellow, never see-through.
        return [star(size + max(1, size * 0.18), .black), star(size, CodableColor(red: 1 * (0.8 + 0.2 * alpha), green: 0.85 * alpha + 0.1, blue: 0.2 * alpha, alpha: 1))]
    }

    @discardableResult func addDizzyStars(count: Int = 3) -> Int {
        guard frames.count >= 2, count > 0, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let radius = max(14, local.width * 0.4), size = max(6, radius * 0.32)
        checkpoint("Dizzy stars")
        let layer = ArtLayer(name: L("Dizzy stars"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let c = CGPoint(x: local.midX, y: local.minY - size * 1.3).applying(matrix(s.transform))
                let t = Double(i - r.lowerBound) / Double(r.count)
                let stars = (0..<count).map { Studio.dizzyStar($0, of: count, t: t, centre: c, radius: radius * s.transform.scale) }
                    .sorted { $0.1 < $1.1 }                                // back ones first
                l.strokes = stars.flatMap { Studio.starStrokes(at: $0.0, size: size * $0.1 * s.transform.scale, alpha: $0.2) }
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return r.count
    }
}
