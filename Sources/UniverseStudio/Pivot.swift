import Foundation
import CoreGraphics

/// Pivots for the layer effects (0.191). A layer's transform turns and scales around the middle of
/// the canvas; effects that turn, grow or stretch a layer should do it around the drawing itself.
/// `pivotEdit` changes a transform and then moves the layer so the chosen point of its drawing –
/// the middle, or the bottom middle so a figure stays on the ground – stays where it was on screen.
extension Studio {
    enum Pivot { case centre, bottom }

    func pivotPoint(_ layer: ArtLayer, _ p: Pivot) -> CGPoint? {
        guard let b = contentBounds(layer) else { return nil }
        return p == .centre ? CGPoint(x: b.midX, y: b.midY) : CGPoint(x: b.midX, y: b.maxY)
    }

    func pivotEdit(_ layer: inout ArtLayer, _ p: Pivot, _ edit: (inout LayerTransform) -> Void) {
        let old = layer.transform
        edit(&layer.transform)
        guard let local = pivotPoint(layer, p) else { return }
        let a = local.applying(matrix(old)), b = local.applying(matrix(layer.transform))
        layer.transform.x += a.x - b.x; layer.transform.y += a.y - b.y
    }
}
