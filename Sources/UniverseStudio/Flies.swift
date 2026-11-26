import Foundation
import CoreGraphics

/// Animation → Effects → Flies (0.273): little black flies buzz around the top of the active layer
/// on their own wandering loops, their pale wings flapping every frame. Seamless over the play range
/// (or all frames). Follows the layer. On a new layer above it. One undo step.
extension Studio {
    static func flyStrokes(at p: CGPoint, size: Double, wingsUp: Bool) -> [InkStroke] {
        let wing = CodableColor(red: 0.85, green: 0.92, blue: 1, alpha: 0.8), lift = wingsUp ? -size * 0.7 : -size * 0.25
        return [oval(CGPoint(x: p.x - size * 0.45, y: p.y + lift), rx: size * 0.4, ry: size * 0.55, wing),
                oval(CGPoint(x: p.x + size * 0.45, y: p.y + lift), rx: size * 0.4, ry: size * 0.55, wing),
                oval(p, rx: size * 0.5, ry: size * 0.38, .black)]
    }

    @discardableResult func addFlies(count: Int = 3) -> Int {
        guard frames.count >= 2, count > 0, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let size = max(4, min(local.width, local.height) * 0.07), radius = max(12, local.width * 0.45)
        let centre = CGPoint(x: local.midX, y: local.minY - local.height * 0.1)
        checkpoint("Flies")
        let layer = ArtLayer(name: L("Flies"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let k = i - r.lowerBound, m = matrix(s.transform)
                l.strokes = (0..<count).flatMap { n -> [InkStroke] in
                    let o = Studio.wanderOffset(k, of: r.count, radius: radius, seed: 0xF1E5 &+ UInt64(n) &* 977)
                    let p = CGPoint(x: centre.x + o.0, y: centre.y + o.1 * 0.6).applying(m)
                    return Studio.flyStrokes(at: p, size: size * s.transform.scale, wingsUp: (k + n) % 2 == 0)
                }
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return count
    }
}
