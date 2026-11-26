import Foundation
import CoreGraphics

/// Animation → Effects → Comet tail (0.228): a ribbon trails behind the middle of the active layer
/// along the way it actually came – wide and strong right behind it, thinner and paler further
/// back. A comet, a magic wand, a firework rocket, a speeding ball. In the brush colour, on a new
/// layer below the active one. Works on the play range if set. One undo step. Returns how many
/// frames got a tail.
extension Studio {
    /// Tail segments (from older to newer) for the path points up to and including the current one.
    static func tailStrokes(_ path: [CGPoint], width: Double, colour: CodableColor) -> [InkStroke] {
        guard path.count >= 2 else { return [] }
        let n = path.count - 1
        return (0..<n).compactMap { s in
            let a = path[s], b = path[s + 1]
            guard hypot(b.x - a.x, b.y - a.y) > 0.5 else { return nil }
            let strength = Double(s + 1) / Double(n)                 // 1 = right behind the layer
            var c = colour; c.alpha = colour.alpha * (0.15 + 0.7 * strength)
            return InkStroke(points: [InkPoint(x: a.x, y: a.y, pressure: 1), InkPoint(x: b.x, y: b.y, pressure: 1)],
                             color: c, width: max(1, width * (0.25 + 0.75 * strength)))
        }
    }

    @discardableResult func addCometTail(length: Int, colour: CodableColor? = nil) -> Int {
        guard frames.count >= 2, length >= 1, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let centre = CGPoint(x: local.midX, y: local.midY)
        let pts: [CGPoint?] = frames.indices.map { i in frames[i].first { $0.id == src.id }.map { centre.applying(matrix($0.transform)) } }
        let w = max(3, min(local.width, local.height) * 0.6)
        var perFrame: [Int: [InkStroke]] = [:]
        for i in r {
            let from = max(r.lowerBound, i - length)
            let path = (from...i).compactMap { pts[$0] }
            let strokes = Studio.tailStrokes(path, width: w, colour: colour ?? color)
            if !strokes.isEmpty { perFrame[i] = strokes }
        }
        guard !perFrame.isEmpty else { return 0 }
        checkpoint("Comet tail")
        let layer = ArtLayer(name: L("Comet tail"))
        for i in frames.indices {
            var l = layer; l.strokes = perFrame[i] ?? []
            frames[i].insert(l, at: frames[i].firstIndex { $0.id == src.id } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return perFrame.count
    }
}
