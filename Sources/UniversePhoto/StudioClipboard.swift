import AppKit
import CoreGraphics

/// Copy, cut, paste and floating selections.
extension Studio {
    /// The active layer's pixels as they sit in the document (transform applied, no opacity/blend).
    func placedLayerPixels() -> CGImage? {
        guard var layer = activeLayer else { return nil }
        layer.opacity = 1; layer.blend = .normal; layer.visible = true; layer.clipped = false
        return Renderer.render(layers: [layer], width: width, height: height)
    }

    /// Pixels inside the selection (everything without one), document size, transparent elsewhere.
    func selectedPixels(merged: Bool) -> CGImage? {
        guard let source = merged ? Renderer.render(layers: layers, width: width, height: height) : placedLayerPixels() else { return nil }
        guard let mask = selectionMask(), let gray = PixelOps.grayImage(mask, width: width, height: height),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        let r = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.clip(to: r, mask: gray)          // unflipped context: image and mask are both upright
        ctx.draw(source, in: r)
        return ctx.makeImage()
    }

    /// The selection as a stroke clip (PNG mask), nil without a selection.
    func selectionClipData() -> Data? {
        if let data = selection?.maskData { return data }
        guard let mask = selectionMask(), let gray = PixelOps.grayImage(mask, width: width, height: height) else { return nil }
        return PixelOps.png(gray)
    }

    func copySelection(merged: Bool = false) {
        guard let image = selectedPixels(merged: merged) else { return }
        copiedPixels = image
        // Other apps get the selected part only, trimmed to its box.
        let box = selection.map { $0.bounds.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height)) } ?? CGRect(x: 0, y: 0, width: width, height: height)
        let trimmed = box.isEmpty ? image : (image.cropping(to: box) ?? image)
        let pb = pasteboard
        pb.clearContents()
        if let png = PixelOps.png(trimmed) { pb.setData(png, forType: .png) }
        pb.writeObjects([NSImage(cgImage: trimmed, size: NSSize(width: trimmed.width, height: trimmed.height))])
        copiedChangeCount = pb.changeCount
    }

    /// Clears the selected pixels of the active layer (an eraser fill clipped to the selection).
    func clearSelection(label: String = "Clear selection") {
        guard canEdit, selection != nil, let clip = selectionClipData() else { return }
        checkpoint(label)
        var erase = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .black, width: 1, isEraser: true)
        erase.kind = "fill"; erase.selectionMask = clip
        layers[selectedLayer].strokes.append(erase)
        changed()
    }

    func cutSelection() {
        guard canEdit, selection != nil else { return }
        copySelection()
        clearSelection(label: "Cut")
    }

    /// Pastes as a new layer: our own copy lands where it came from, other pictures centred
    /// (scaled down to fit when larger than the document).
    func paste() {
        guard !isPlaying else { return }
        let pb = pasteboard
        var picture: CGImage?
        if pb.changeCount == copiedChangeCount, let own = copiedPixels, own.width == width, own.height == height { picture = own }
        else if let image = NSImage(pasteboard: pb), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            picture = centred(cg)
        }
        guard let picture, let data = PixelOps.png(picture) else { return }
        checkpoint("Paste")
        var layer = ArtLayer(name: L("Pasted")); layer.imageData = data
        layers.insert(layer, at: min(selectedLayer + 1, layers.count)); selectedLayer = min(selectedLayer + 1, layers.count - 1)
        maskEditing = false; changed()
    }

    private func centred(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let scale = min(1, Double(width) / Double(image.width), Double(height) / Double(image.height))
        let w = Double(image.width) * scale, h = Double(image.height) * scale
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: (Double(width) - w) / 2, y: (Double(height) - h) / 2, width: w, height: h))
        return ctx.makeImage()
    }

    /// New layer from the selected pixels; `cut` also clears them on the source layer.
    func layerFromSelection(cut: Bool) {
        guard selection != nil, let image = selectedPixels(merged: false), let data = PixelOps.png(image) else { duplicateLayer(); return }
        if cut && !canEdit { return }
        checkpoint(cut ? "Layer via cut" : "Layer via copy")
        if cut, let clip = selectionClipData() {
            var erase = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .black, width: 1, isEraser: true)
            erase.kind = "fill"; erase.selectionMask = clip
            layers[selectedLayer].strokes.append(erase)
        }
        var layer = ArtLayer(name: (activeLayer?.name ?? L("Layer")) + (cut ? L(" cut") : L(" copy"))); layer.imageData = data
        layers.insert(layer, at: selectedLayer + 1); selectedLayer += 1
        selection = nil; maskEditing = false; changed()
    }

    func toggleClipping() {
        guard selectedLayer > 0 else { return }
        mutateLayer("Clipping mask") { $0.clipped.toggle() }
    }
}

/// ⌘C/⌘X/⌘V/⌘A go to a text field while one is being edited.
@MainActor func forwardToTextField(_ action: Selector) -> Bool {
    guard NSApp.keyWindow?.firstResponder is NSText else { return false }
    NSApp.sendAction(action, to: nil, from: nil)
    return true
}
