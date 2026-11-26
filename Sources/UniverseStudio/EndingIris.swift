import Foundation
import CoreGraphics

/// Animation → Effects → Camera → Ending (0.293): the classic cartoon ending for the whole picture –
/// black closes in as a shrinking circle or heart around the middle (or around the active layer, if
/// it has a drawing) until the picture is black. One black layer on top whose mask keeps a hole open.
/// Over the play range (or all frames); after it, the picture stays black. Opening (0.294) is the
/// same backwards: black before the range, then the hole grows until the picture is clear. One undo step.
extension Studio {
    @discardableResult func addEndingIris(heart: Bool, opening: Bool = false) -> Int {
        guard frames.count >= 2 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let w = Double(width), h = Double(height)
        var c = CGPoint(x: w / 2, y: h / 2)
        if let l = activeLayer, l.allFrames != true, let b = contentBounds(l) { c = CGPoint(x: b.midX, y: b.midY).applying(matrix(l.transform)) }
        // Big enough to clear the farthest corner from the centre.
        let full = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), CGPoint(x: w, y: h)].map { hypot($0.x - c.x, $0.y - c.y) }.max()!
        let factor = heart ? Studio.heartCoverFactor(width: 2 * max(c.x, w - c.x), height: 2 * max(c.y, h - c.y)) : 2
        checkpoint(opening ? "Opening" : "Ending")
        var black = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .maskBlack, width: 1); black.kind = "fill"
        var shown = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1); shown.kind = "fill"
        let layer = { () -> ArtLayer in var l = ArtLayer(name: L(opening ? "Opening" : "Ending")); l.strokes = [black]; return l }()
        for i in frames.indices {
            var l = layer
            if opening ? i > r.upperBound : i < r.lowerBound { l.visible = false }
            else if i <= r.upperBound {
                var p = Studio.fadeRamp(i - r.lowerBound, of: r.count, fadeIn: true)
                if opening { p = 1 - p }
                let rad = full * (1 - p)
                if rad > 1e-9 {
                    var hole: InkStroke
                    if heart { hole = Studio.polygon(Studio.heartOutline(cx: c.x, cy: c.y, rad: rad * rad / full, factor: factor), .maskBlack) }
                    else {
                        hole = InkStroke(points: [InkPoint(x: c.x - rad, y: c.y - rad, pressure: 1), InkPoint(x: c.x + rad, y: c.y + rad, pressure: 1)], color: .maskBlack, width: 1)
                        hole.kind = "ellipse"; hole.filled = true
                    }
                    l.mask = [shown, hole]                       // black everywhere except the hole
                }
            }
            frames[i].append(l)
        }
        layers = frames[frameIndex]; selectedLayer = layers.count - 1
        changed()
        return r.count
    }
}
