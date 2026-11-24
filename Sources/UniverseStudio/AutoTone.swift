import CoreGraphics

/// Image → Auto tone / Auto contrast: measure the active layer's pixels and stretch them so the
/// darkest 0.1 % become black and the lightest 0.1 % white. Written into the layer's adjustment
/// (levels or per-channel curves), so it stays editable and can be undone.
enum AutoTone {
    /// Pixel counts per value for red, green, blue and luminance (transparent pixels skipped).
    static func histograms(_ image: CGImage) -> [[Double]] {
        let w = min(512, image.width), h = max(1, Int(Double(image.height) * Double(w) / Double(max(1, image.width))))
        var out = [[Double]](repeating: [Double](repeating: 0, count: 256), count: 4)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return out }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(w * h) {
            let a = Double(px[i * 4 + 3]); guard a > 8 else { continue }
            let r = Double(px[i * 4]) * 255 / a, g = Double(px[i * 4 + 1]) * 255 / a, b = Double(px[i * 4 + 2]) * 255 / a
            for (c, v) in [r, g, b, 0.2126 * r + 0.7152 * g + 0.0722 * b].enumerated() { out[c][min(255, max(0, Int(v.rounded())))] += 1 }
        }
        return out
    }

    /// Values (0…1) below and above which `clip` of the pixels lie; nil for an empty or flat picture.
    static func range(_ counts: [Double], clip: Double = 0.001) -> (Double, Double)? {
        let total = counts.reduce(0, +); guard total > 0 else { return nil }
        var acc = 0.0, lo = 0, hi = 255
        for (i, c) in counts.enumerated() { acc += c; if acc > total * clip { lo = i; break } }
        acc = 0
        for (i, c) in counts.enumerated().reversed() { acc += c; if acc > total * clip { hi = i; break } }
        guard hi - lo >= 2 else { return nil }
        return (Double(lo) / 255, Double(hi) / 255)
    }
}

extension Studio {
    /// What the auto commands measure: the layer's own pixels, or for an adjustment layer the
    /// picture below it. Its current levels and curves are left out, so running it twice is stable.
    func autoToneSource() -> CGImage? {
        guard layers.indices.contains(selectedLayer) else { return nil }
        var layer = layers[selectedLayer]
        if layer.isAdjustmentLayer { return Renderer.render(layers: composite(Array(layers[..<selectedLayer])), width: width, height: height) }
        layer.opacity = 1; layer.blend = .normal; layer.visible = true; layer.clipped = false
        layer.adjustment.levelsBlack = 0; layer.adjustment.levelsWhite = 1; layer.adjustment.curves = nil
        return Renderer.render(layers: [layer], width: width, height: height)
    }

    /// Stretches the brightness (levels black and white point). Returns false when there is nothing to stretch.
    @discardableResult func autoContrast() -> Bool {
        guard canEdit, let img = autoToneSource(), let (lo, hi) = AutoTone.range(AutoTone.histograms(img)[3]) else { return false }
        mutateLayer("Auto contrast") { $0.adjustment.levelsBlack = lo; $0.adjustment.levelsWhite = hi }
        return true
    }

    /// Stretches each colour channel on its own (removes colour casts too), as per-channel curves.
    @discardableResult func autoTone() -> Bool {
        guard canEdit, let img = autoToneSource() else { return false }
        let h = AutoTone.histograms(img)
        var curves = activeLayer?.adjustment.curves ?? [:]
        var changed = false
        for (i, ch) in ["red", "green", "blue"].enumerated() {
            guard let (lo, hi) = AutoTone.range(h[i]) else { continue }
            curves[ch] = [CurvePoint(x: lo, y: 0), CurvePoint(x: hi, y: 1)]; changed = true
        }
        guard changed else { return false }
        mutateLayer("Auto tone") { $0.adjustment.curves = curves; $0.adjustment.levelsBlack = 0; $0.adjustment.levelsWhite = 1 }
        return true
    }
}
