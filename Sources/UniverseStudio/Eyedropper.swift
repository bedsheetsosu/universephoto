import SwiftUI

/// Eyedropper options: average over a square of pixels (1, 3, 5, 11, 31) and pick from all
/// visible layers or the active layer only.
extension Studio {
    static let sampleSizes = [1, 3, 5, 11, 31]

    /// The colour at `p` (document pixels) as the eyedropper sees it, or nil outside / transparent.
    func pickColor(at p: CGPoint, from composite: CGImage? = nil) -> CodableColor? {
        let image: CGImage?, point: CGPoint
        if eyedropperAllLayers {
            image = composite ?? Renderer.render(layers: self.composite(layers), width: width, height: height); point = p
        } else {
            guard let layer = activeLayer else { return nil }
            image = sampledImage(merged: false); point = p.applying(matrix(layer.transform).inverted())
        }
        guard let image else { return nil }
        let c = Renderer.sampleAverage(image, at: point, size: eyedropperSize)
        return c.alpha > 0 ? c : nil
    }
}

extension Renderer {
    /// Average colour of the `size` × `size` square around `point` (transparent pixels count less,
    /// like Photoshop: the average is taken premultiplied, then un-premultiplied).
    static func sampleAverage(_ image: CGImage, at point: CGPoint, size: Int) -> CodableColor {
        guard size > 1 else { return sample(image, at: point) }
        let r = size / 2, cx = Int(floor(point.x)), cy = Int(floor(point.y))
        let box = CGRect(x: cx - r, y: cy - r, width: size, height: size).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !box.isNull, box.width >= 1, box.height >= 1, let crop = image.cropping(to: box), let bitmap = PixelOps.bitmap(crop) else { return CodableColor(red: 0, green: 0, blue: 0, alpha: 0) }
        var sum = [Double](repeating: 0, count: 4)
        for i in stride(from: 0, to: bitmap.bytes.count, by: 4) { for k in 0..<4 { sum[k] += Double(bitmap.bytes[i + k]) } }
        let n = Double(bitmap.width * bitmap.height), a = sum[3] / n / 255
        guard a > 0 else { return CodableColor(red: 0, green: 0, blue: 0, alpha: 0) }
        return CodableColor(red: min(1, sum[0] / n / 255 / a), green: min(1, sum[1] / n / 255 / a), blue: min(1, sum[2] / n / 255 / a), alpha: a)
    }
}
