import CoreGraphics

/// Image → Remove red eye: inside the selection (draw a circle or rectangle around each pupil),
/// pixels where red clearly outweighs green and blue lose that red and get a little darker,
/// softly by how red they were. Skin around the pupil is barely red-dominant and stays.
extension Studio {
    /// The corrected colour and how strongly it applies (0…1), for one unpremultiplied pixel.
    static func redEyeFix(r: Double, g: Double, b: Double) -> (Double, Double, Double, Double) {
        let other = (g + b) / 2
        // Red has to be strong and well above the others; ramps in between ratio 1.8 and 2.6 (skin stays below 1.8).
        let ratio = r / max(0.02, other)
        let w = max(0, min(1, (ratio - 1.8) / 0.8)) * max(0, min(1, (r - 0.25) / 0.2))
        guard w > 0 else { return (r, g, b, 0) }
        let dark = 0.8
        return (other * dark, g * dark, b * dark, w)
    }

    /// Returns how many pixels changed; 0 without a selection or red pixels.
    @discardableResult func removeRedEye() -> Int {
        guard canEdit, let layer = activeLayer, !layer.isAdjustmentLayer, let sel = selectionInLayerPixels(),
              let image = rawLayerPixels(), let bm = PixelOps.bitmap(image) else { return 0 }
        var out = [UInt8](repeating: 0, count: bm.bytes.count), changed = 0
        for i in 0..<(bm.width * bm.height) where sel[i] > 0 {
            let p = i * 4, a = Double(bm.bytes[p + 3]) / 255
            guard a > 0 else { continue }
            let (nr, ng, nb, w0) = Self.redEyeFix(r: Double(bm.bytes[p]) / 255 / a, g: Double(bm.bytes[p + 1]) / 255 / a, b: Double(bm.bytes[p + 2]) / 255 / a)
            let w = w0 * Double(sel[i]) / 255
            guard w > 0.01 else { continue }
            changed += 1
            out[p] = UInt8(min(255, nr * w * 255)); out[p + 1] = UInt8(min(255, ng * w * 255)); out[p + 2] = UInt8(min(255, nb * w * 255)); out[p + 3] = UInt8(min(255, w * 255))
        }
        guard changed > 0, let picture = ContentAwareFill.image(out, width: width, height: height), let data = PixelOps.png(picture) else { return 0 }
        var stroke = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1)
        stroke.kind = "bitmap"; stroke.imageData = data; stroke.atop = true
        mutateLayer("Remove red eye") { $0.strokes.append(stroke) }
        return changed
    }
}
