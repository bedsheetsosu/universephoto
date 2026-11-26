import Foundation
import CoreGraphics

/// Animation → Effects → Tears (0.267): crying – drops well up at eye height on both sides of the
/// active layer and roll down its cheeks one after another, slightly outwards, fading at the bottom.
/// Two drops per eye per loop, a seamless loop over the play range (or all frames). Follows the
/// layer. On a new layer above it. One undo step.
extension Studio {
    /// Where a tear of age `t` (0…1) is, relative to its eye: (dx factor of `side`, dy 0…1, size, alpha).
    static func tearState(_ t: Double) -> (out: Double, down: Double, size: Double, alpha: Double) {
        let grow = min(1, t / 0.2), fall = t < 0.2 ? 0 : (t - 0.2) / 0.8
        return (fall * 0.35, fall, 0.5 + 0.5 * grow, t > 0.8 ? max(0, 1 - (t - 0.8) / 0.2) : 1)
    }

    @discardableResult func addTears(perEye: Int = 2) -> Int {
        guard frames.count >= 2, perEye > 0, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let size = max(4, min(local.width, local.height) * 0.12), fallBy = local.height * 0.5
        let eyes = [-1.0, 1.0].map { (side: $0, at: CGPoint(x: local.midX + $0 * local.width * 0.2, y: local.minY + local.height * 0.32)) }
        checkpoint("Tears")
        let layer = ArtLayer(name: L("Tears"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let m = matrix(s.transform), t = Double(i - r.lowerBound) / Double(r.count)
                for e in eyes {
                    for j in 0..<perEye {
                        let age = (t + Double(j) / Double(perEye) + (e.side > 0 ? 0.5 / Double(perEye) : 0)).truncatingRemainder(dividingBy: 1)
                        let st = Studio.tearState(age)
                        let p = CGPoint(x: e.at.x + e.side * size * 4 * st.out, y: e.at.y + fallBy * st.down).applying(m)
                        l.strokes += Studio.dropStrokes(at: p, size: size * st.size * s.transform.scale, alpha: st.alpha)
                    }
                }
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return perEye * 2
    }
}
