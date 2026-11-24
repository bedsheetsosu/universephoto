import CoreGraphics
import Foundation

/// Animate → Motion path (0.88): the centre of the active layer's drawing in every frame, joined
/// by a line on the canvas, so spacing and arcs of a movement can be judged at a glance.
extension Studio {
    static let motionPathMaxFrames = 240

    /// Centre per frame in document pixels (nil where the layer is missing or empty).
    func motionPathPoints() -> [CGPoint?] {
        guard frames.count > 1, frames.count <= Self.motionPathMaxFrames, let id = activeLayer?.id else { return [] }
        return frames.indices.map { i in
            let frame = i == frameIndex ? layers : frames[i]
            guard let layer = frame.first(where: { $0.id == id }), !layer.isAdjustmentLayer, let box = contentBounds(layer) else { return nil }
            return CGPoint(x: box.midX, y: box.midY).applying(matrix(layer.transform))
        }
    }

    /// Whether the path says anything: at least two frames where the centre differs.
    static func pathMoves(_ points: [CGPoint?]) -> Bool {
        let p = points.compactMap { $0 }
        guard let first = p.first else { return false }
        return p.contains { hypot($0.x - first.x, $0.y - first.y) > 0.5 }
    }
}
