import CoreGraphics
import Foundation

/// Free transform (⌘T) and aligning layers to the canvas.
extension Studio {
    /// Layer coordinates → document coordinates (the pivot is the document centre).
    func matrix(_ t: LayerTransform) -> CGAffineTransform {
        CGAffineTransform(translationX: t.x + Double(width) / 2, y: t.y + Double(height) / 2)
            .rotated(by: t.rotation * .pi / 180).scaledBy(x: t.scale, y: t.scale)
            .translatedBy(x: -Double(width) / 2, y: -Double(height) / 2)
    }

    /// Box around the visible pixels of a layer, in its own coordinates (nil when empty).
    func contentBounds(_ layer: ArtLayer) -> CGRect? {
        let key = "\(layer.id)-\(layer.strokes.count)-\(layer.strokes.last?.id.uuidString ?? "")-\(layer.imageData?.count ?? 0)-\(width)x\(height)"
        if let hit = boundsCache[key] { return hit.isNull ? nil : hit }
        var l = layer
        l.opacity = 1; l.blend = .normal; l.transform = .init(); l.visible = true; l.adjustment = .init(); l.clipped = false; l.style = nil
        var box = CGRect.null
        if let image = Renderer.render(layers: [l], width: width, height: height), let b = PixelOps.bitmap(image) {
            var alpha = [UInt8](repeating: 0, count: width * height)
            for i in 0..<(width * height) { alpha[i] = b.bytes[i * 4 + 3] }
            box = PixelOps.bounds(alpha, width: width, height: height) ?? .null
        }
        if boundsCache.count > 64 { boundsCache.removeAll() }
        boundsCache[key] = box
        return box.isNull ? nil : box
    }

    /// The four corners of the active layer's content in document coordinates (TL, TR, BR, BL).
    func transformCorners() -> [CGPoint]? {
        guard let layer = activeLayer, let box = contentBounds(layer) else { return nil }
        let m = matrix(layer.transform)
        return [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)].map { $0.applying(m) }
    }

    /// New transform with `scale` and `rotation`, keeping the content's centre where it is on screen.
    func transformKeepingCentre(from start: LayerTransform, scale: Double, rotation: Double) -> LayerTransform {
        guard let layer = activeLayer, let box = contentBounds(layer) else { return start }
        let local = CGPoint(x: box.midX, y: box.midY)
        let fixed = local.applying(matrix(start))
        var t = start; t.scale = max(0.01, min(100, scale)); t.rotation = rotation
        t.x = 0; t.y = 0
        let moved = local.applying(matrix(t))
        t.x = fixed.x - moved.x; t.y = fixed.y - moved.y
        return t
    }

    enum Alignment: String, CaseIterable { case left, centerX, right, top, centerY, bottom }

    /// Moves the selected layers so their content lines up with the canvas edge or centre.
    func align(_ a: Alignment) {
        let targets = selectedIndices.filter { !layers[$0].locked }
        guard !targets.isEmpty else { return }
        checkpoint("Align")
        for i in targets {
            guard let box = contentBounds(layers[i]) else { continue }
            let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)].map { $0.applying(matrix(layers[i].transform)) }
            let minX = corners.map(\.x).min()!, maxX = corners.map(\.x).max()!, minY = corners.map(\.y).min()!, maxY = corners.map(\.y).max()!
            switch a {
            case .left: layers[i].transform.x -= minX
            case .right: layers[i].transform.x += Double(width) - maxX
            case .centerX: layers[i].transform.x += Double(width) / 2 - (minX + maxX) / 2
            case .top: layers[i].transform.y -= minY
            case .bottom: layers[i].transform.y += Double(height) - maxY
            case .centerY: layers[i].transform.y += Double(height) / 2 - (minY + maxY) / 2
            }
        }
        changed()
    }

    func resetTransform() { mutateLayer("Reset transform") { $0.transform = .init() } }
}
