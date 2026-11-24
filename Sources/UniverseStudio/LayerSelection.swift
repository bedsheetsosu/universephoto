import AppKit

/// Select → Load layer transparency (⌘-click a layer's thumbnail): the layer's opaque pixels,
/// where it sits on the canvas, become the selection; ⇧ adds, ⌥ subtracts, ⇧⌥ intersects.
/// Also: Save selection / Load selection keep up to one selection per document while the app runs.
extension Studio {
    enum MaskCombine { case replace, add, subtract, intersect }

    /// `mask` combined with the current selection.
    func combine(_ mask: [UInt8], _ how: MaskCombine) -> [UInt8] {
        guard how != .replace, let current = selectionMask() else { return how == .subtract || how == .intersect ? [UInt8](repeating: 0, count: mask.count) : mask }
        switch how {
        case .add: return zip(current, mask).map { max($0, $1) }
        case .subtract: return zip(current, mask).map { UInt8(Int($0) * (255 - Int($1)) / 255) }
        case .intersect: return zip(current, mask).map { UInt8(Int($0) * Int($1) / 255) }
        case .replace: return mask
        }
    }

    /// Alpha of layer `index` as placed on the canvas (transform and mask, no opacity or effects).
    func layerAlpha(_ index: Int) -> [UInt8]? {
        guard layers.indices.contains(index), !layers[index].isAdjustmentLayer else { return nil }
        var l = layers[index]
        l.opacity = 1; l.blend = .normal; l.visible = true; l.clipped = false; l.style = nil; l.filters = nil; l.adjustment = .init()
        guard let img = Renderer.render(layers: [l], width: width, height: height), let b = PixelOps.bitmap(img) else { return nil }
        return stride(from: 3, to: b.bytes.count, by: 4).map { b.bytes[$0] }
    }

    func loadLayerTransparency(_ index: Int? = nil, _ how: MaskCombine = .replace) {
        guard let alpha = layerAlpha(index ?? selectedLayer) else { return }
        setSelection(mask: combine(alpha, how))
    }

    static func maskCombine(_ flags: NSEvent.ModifierFlags) -> MaskCombine {
        let shift = flags.contains(.shift), option = flags.contains(.option)
        return shift && option ? .intersect : shift ? .add : option ? .subtract : .replace
    }

    func saveSelection() { savedSelectionsByTab[tabID] = selectionMask() }
    func loadSavedSelection(_ how: MaskCombine = .replace) {
        guard let m = savedSelectionsByTab[tabID] else { return }
        setSelection(mask: combine(m, how))
    }
    var hasSavedSelection: Bool { savedSelectionsByTab[tabID] != nil }
}
