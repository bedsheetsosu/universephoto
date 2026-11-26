import Foundation
import CoreGraphics

/// Animation → Layer effects → Pop (0.226): the active layer bursts like a balloon on the current
/// frame – it swells for a few frames before, then it's gone and a little burst of sparks or
/// confetti flies out where it was. Scrub to the frame where it should pop first. The burst goes on
/// a new layer above. One undo step. Returns the frame it pops on.
extension Studio {
    /// Size factor for a layer `before` frames ahead of the pop (1, 2, 3 → swelling).
    static func popSwell(before: Int) -> Double {
        switch before { case 1: 1.22; case 2: 1.12; case 3: 1.05; default: 1 }
    }

    @discardableResult func popAway(_ style: BurstStyle = .sparks) -> Int {
        guard frames.count >= 2, let src = activeLayer, src.allFrames != true, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        frames[frameIndex] = layers
        let pop = frameIndex
        guard let at = frames[pop].first(where: { $0.id == src.id }) else { return 0 }
        let box = local.applying(matrix(at.transform))
        let centre = CGPoint(x: box.midX, y: box.midY), size = max(40, max(box.width, box.height) * 2.2)
        checkpoint("Burst like a balloon")
        for b in 1...3 where pop - b >= 0 {
            for j in frames[pop - b].indices where frames[pop - b][j].id == src.id {
                let f = Studio.popSwell(before: b)
                pivotEdit(&frames[pop - b][j], .centre) { $0.scale *= f }
            }
        }
        for i in pop..<frames.count { for j in frames[i].indices where frames[i][j].id == src.id { frames[i][j].opacity = 0 } }
        let length = max(3, Int((fps * 0.6).rounded()))
        let burst = ArtLayer(name: L("Burst like a balloon"))
        for i in frames.indices {
            var l = burst
            if i >= pop, i < pop + length {
                l.strokes = Studio.burstStrokes(style, t: Double(i - pop + 1) / Double(length), centre: centre, size: size)
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return pop
    }
}
