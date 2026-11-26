import Foundation
import CoreGraphics

/// Animation → Effects → Ray burst (0.270): the "ta-da" background – wedge-shaped rays of light
/// fan out from the middle of the active layer and turn slowly behind it, in the brush colour (gold
/// if that is very dark) and see-through. One ray step per loop, so it is seamless over the play range (or all frames). On a
/// new layer below the active one. One undo step.
extension Studio {
    /// Corner points of all rays at time `t` (0…1): `count` wedges around `c`, reaching `reach`.
    static func rayWedges(count: Int, t: Double, centre c: CGPoint, reach: Double) -> [[CGPoint]] {
        let step = 2 * .pi / Double(count), half = step * 0.25
        return (0..<count).map { k in
            let a = Double(k) * step + t * step
            return [c, CGPoint(x: c.x + cos(a - half) * reach, y: c.y + sin(a - half) * reach),
                    CGPoint(x: c.x + cos(a + half) * reach, y: c.y + sin(a + half) * reach)]
        }
    }

    @discardableResult func addRayBurst(rays: Int = 12) -> Int {
        guard frames.count >= 2, rays >= 3, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let reach = Double(width + height)
        // Very dark brush colours would make grey rays – those get warm gold instead.
        var colour = Studio.glowColour(color)
        colour.alpha = 0.35
        checkpoint("Ray burst")
        let layer = ArtLayer(name: L("Ray burst"))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let c = CGPoint(x: local.midX, y: local.midY).applying(matrix(s.transform))
                let t = Double(i - r.lowerBound) / Double(r.count)
                l.strokes = Studio.rayWedges(count: rays, t: t, centre: c, reach: reach).map { Studio.polygon($0, colour) }
            }
            frames[i].insert(l, at: frames[i].firstIndex { $0.id == src.id } ?? 0)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return r.count
    }
}
