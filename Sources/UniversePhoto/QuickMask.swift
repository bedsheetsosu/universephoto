import CoreGraphics

/// Quick mask: the selection becomes a red, half-transparent layer on top; brush and eraser paint
/// it (any colour paints red, opacity paints partly selected). Leaving turns what is painted back
/// into the selection. Entering and leaving are undo steps; the brush strokes in between too.
extension Studio {
    static let quickMaskRed = CodableColor(red: 1, green: 0.15, blue: 0.2, alpha: 1)

    var quickMaskActive: Bool { quickMaskLayer.map { id in layers.contains { $0.id == id } } ?? false }

    func toggleQuickMask() { quickMaskActive ? exitQuickMask() : enterQuickMask() }

    func enterQuickMask() {
        guard !isPlaying, !quickMaskActive else { return }
        checkpoint("Quick mask")
        var layer = ArtLayer(name: L("Quick mask")); layer.opacity = 0.5
        if let mask = selectionMask(), let image = PixelOps.fillImage(mask, width: width, height: height, color: Self.quickMaskRed), let data = PixelOps.png(image) {
            var s = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: Self.quickMaskRed, width: 1)
            s.kind = "bitmap"; s.imageData = data
            layer.strokes = [s]
        }
        quickMaskReturn = selectedLayer
        layers.append(layer); selectedLayer = layers.count - 1; quickMaskLayer = layer.id
        selection = nil; maskEditing = false
        if ![.brush, .eraser].contains(tool) { tool = .brush }
        changed()
    }

    func exitQuickMask() {
        guard let id = quickMaskLayer, let i = layers.firstIndex(where: { $0.id == id }) else { quickMaskLayer = nil; return }
        var layer = layers[i]
        layer.opacity = 1; layer.visible = true; layer.transform = .init(); layer.blend = .normal
        var mask: [UInt8]?
        if let image = Renderer.render(layers: [layer], width: width, height: height), let b = PixelOps.bitmap(image) {
            mask = (0..<(width * height)).map { b.bytes[$0 * 4 + 3] }
        }
        checkpoint("Quick mask")
        layers.remove(at: i); selectedLayer = min(max(0, quickMaskReturn), layers.count - 1); quickMaskLayer = nil
        if let mask, mask.contains(where: { $0 > 0 }) { setSelection(mask: mask) } else { selection = nil }
        changed()
    }
}
