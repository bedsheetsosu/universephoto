import Foundation
import CoreGraphics

/// Animation → Effects → Light → Spotlight (0.248): the stage goes dark except for a soft circle of
/// light that follows the active layer – a performer on stage, a torch in a cave, the end of a
/// cartoon (with Iris). A dark layer on top whose mask leaves the circle open, with a soft edge made
/// of a few grey rings. Over the play range (or all frames). One undo step.
extension Studio {
    /// Mask rings for a light circle of `radius` at `c`: grey outside to black in the middle (black = open).
    static func spotlightMask(centre c: CGPoint, radius: Double) -> [InkStroke] {
        [(1.35, 0.7), (1.18, 0.4), (1.0, 0)].map { scale, grey in
            let rr = radius * scale
            var e = InkStroke(points: [InkPoint(x: c.x - rr, y: c.y - rr, pressure: 1), InkPoint(x: c.x + rr, y: c.y + rr, pressure: 1)],
                              color: CodableColor(red: grey, green: grey, blue: grey, alpha: 1), width: 1)
            e.kind = "ellipse"; e.filled = true
            return e
        }
    }

    @discardableResult func addSpotlight(darkness: Double = 0.8) -> Int {
        guard frames.count >= 1, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.isEmpty { frames = [layers] }
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let radius = max(20, hypot(local.width, local.height) * 0.65)
        let centre = CGPoint(x: local.midX, y: local.midY)
        checkpoint("Spotlight")
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .maskBlack, width: 1)
        fill.kind = "fill"
        var layer = ArtLayer(name: L("Spotlight")); layer.strokes = [fill]; layer.opacity = darkness
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                l.mask = Studio.spotlightMask(centre: centre.applying(matrix(s.transform)), radius: radius * s.transform.scale)
            } else { l.opacity = 0 }
            frames[i].append(l)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return r.count
    }
}
