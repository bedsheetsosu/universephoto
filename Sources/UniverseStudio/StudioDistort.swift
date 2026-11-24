import CoreImage
import SwiftUI

/// Layer → Distort: four free corners around the layer's content; dragging them bends the
/// picture in perspective (live), ↩ applies, Esc cancels. The result replaces the layer's
/// content with pixels; its position, opacity, blend, mask, style and filters stay.
extension Studio {
    private static let distortContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    var distorting: Bool { distortCorners != nil }

    /// The layer's own pixels in layer coordinates, without effects.
    private func distortPixels() -> CGImage? {
        guard var layer = activeLayer else { return nil }
        layer.opacity = 1; layer.blend = .normal; layer.transform = .init(); layer.visible = true
        layer.mask = nil; layer.adjustment = .init(); layer.clipped = false; layer.style = nil; layer.filters = nil
        return Renderer.render(layers: [layer], width: width, height: height)
    }

    func beginDistort() {
        guard canEdit, !isPlaying, let layer = activeLayer, !layer.isAdjustmentLayer, let raw = distortPixels(), let box = contentBounds(layer) else { return }
        transformMode = false
        let m = matrix(layer.transform)
        distortSource = raw; distortBounds = box
        distortCorners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)].map { $0.applying(m) }
        var preview = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1)
        preview.kind = "liquify"   // drawn as a picture that replaces the layer's pixels
        distortStroke = preview
        Renderer.transient[preview.id] = raw
    }

    /// The layer content warped so its box lands on `corners` (layer pixels: TL, TR, BR, BL).
    static func warped(_ source: CGImage, box: CGRect, corners c: [CGPoint], width w: Int, height h: Int) -> CGImage? {
        guard c.count == 4 else { return nil }
        let H = Double(h)
        func v(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: H - p.y) }   // CI is y-up
        let input = CIImage(cgImage: source).cropped(to: CGRect(x: box.minX, y: H - box.maxY, width: box.width, height: box.height))
        let out = input.applyingFilter("CIPerspectiveTransform", parameters: ["inputTopLeft": v(c[0]), "inputTopRight": v(c[1]), "inputBottomRight": v(c[2]), "inputBottomLeft": v(c[3])])
        return distortContext.createCGImage(out, from: CGRect(x: 0, y: 0, width: w, height: h))
    }

    func moveDistortCorner(_ i: Int, to p: CGPoint) {
        guard var corners = distortCorners, corners.indices.contains(i), let src = distortSource, let box = distortBounds, let layer = activeLayer, let stroke = distortStroke else { return }
        corners[i] = p; distortCorners = corners
        let inv = matrix(layer.transform).inverted()
        if let image = Self.warped(src, box: box, corners: corners.map { $0.applying(inv) }, width: width, height: height) {
            Renderer.transient[stroke.id] = image
        }
    }

    func applyDistort() {
        guard let stroke = distortStroke else { return }
        defer { cancelDistort() }
        guard canEdit, let image = Renderer.transient[stroke.id], let data = try? Renderer.png(image) else { return }
        mutateLayer("Distort") { $0.imageData = data; $0.strokes = [] }
        boundsCache.removeAll()
    }

    func cancelDistort() {
        if let id = distortStroke?.id { Renderer.transient[id] = nil }
        distortCorners = nil; distortSource = nil; distortBounds = nil; distortStroke = nil
    }
}
