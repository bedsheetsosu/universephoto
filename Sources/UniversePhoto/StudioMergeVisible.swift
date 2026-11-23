import CoreGraphics
import Foundation

/// Layers → Merge visible, Flatten image and Stamp visible: the picture as shown, baked into one
/// raster layer (with transparency; groups, masks, effects and adjustments applied).
extension Studio {
    private func visibleRaster(_ list: [ArtLayer]) -> Data? {
        guard let image = Renderer.render(layers: composite(list), width: width, height: height) else { return nil }
        return try? Renderer.png(image)
    }

    /// Visible layers become one (at the topmost visible layer's place); hidden ones stay.
    func mergeVisible() {
        let visible = layers.indices.filter { layers[$0].visible }
        guard visible.count > 1, !isPlaying, !layers.contains(where: { $0.visible && $0.locked }), let data = visibleRaster(layers) else { return }
        checkpoint("Merge visible")
        var merged = ArtLayer(name: layers[visible.last!].name); merged.imageData = data
        var out: [ArtLayer] = []
        for (i, l) in layers.enumerated() {
            if i == visible.last { out.append(merged) } else if !l.visible { out.append(l) }
        }
        layers = out
        selectedLayer = out.firstIndex { $0.id == merged.id } ?? 0
        selectedIDs = []; maskEditing = false; boundsCache.removeAll()
        changed()
    }

    /// Everything visible becomes one layer; hidden layers are dropped.
    func flattenImage() {
        guard layers.count > 1, !isPlaying, let data = visibleRaster(layers) else { return }
        checkpoint("Flatten image")
        var flat = ArtLayer(name: L("Background")); flat.imageData = data
        layers = [flat]; selectedLayer = 0; selectedIDs = []; maskEditing = false; boundsCache.removeAll()
        changed()
    }

    /// A new layer on top with the picture as shown; the others stay untouched.
    func stampVisible() {
        guard !isPlaying, let data = visibleRaster(layers) else { return }
        checkpoint("Stamp visible")
        var stamp = ArtLayer(name: L("Stamp")); stamp.imageData = data
        layers.append(stamp); selectedLayer = layers.count - 1; selectedIDs = []; maskEditing = false
        changed()
    }
}
