import AppKit
import CoreGraphics
import CoreImage

/// Smudge in progress: the layer's pixels being pushed around, the paint the brush carries,
/// and which pixels it has touched.
struct SmudgeState {
    var bitmap: PixelOps.Bitmap
    var carried: [Double] = []          // RGBA premultiplied, (2r+1)² samples around the brush
    var radius = 0
    var last: CGPoint
    var touched: [UInt8]
}

/// Clone stamp, healing brush and smudge.
extension Studio {
    /// The active layer's own pixels: strokes and picture, no mask, adjustments or transform.
    func rawLayerPixels() -> CGImage? {
        guard var layer = activeLayer else { return nil }
        layer.opacity = 1; layer.blend = .normal; layer.transform = .init(); layer.visible = true
        layer.mask = nil; layer.adjustment = .init(); layer.clipped = false
        return Renderer.render(layers: [layer], width: width, height: height)
    }

    /// Option-click: where the clone stamp and healing brush copy from.
    func setCloneSource(_ point: CGPoint) { cloneSource = point; cloneOffset = nil }

    /// Prepares a clone/heal stroke starting at `point`; false without a source.
    func beginClone(id: UUID, at point: CGPoint) -> Bool {
        guard let source = cloneSource else { message = "Option-click to set the source first."; return false }
        let offset = (cloneAligned ? cloneOffset : nil) ?? CGSize(width: source.x - point.x, height: source.y - point.y)
        cloneOffset = offset
        guard let picture = sampleMerged ? Renderer.render(layers: composite(layers), width: width, height: height) : rawLayerPixels(),
              let ctx = Renderer.context(width: width, height: height) else { return false }
        // Pixel (x, y) of the result shows the source at (x + dx, y + dy).
        Renderer.drawImage(picture, in: ctx, rect: CGRect(x: -offset.width, y: -offset.height, width: Double(width), height: Double(height)))
        Renderer.transient[id] = ctx.makeImage()
        return true
    }

    /// Where the source currently is under a brush at `point` (for the crosshair).
    func cloneSourceMarker(for point: CGPoint) -> CGPoint? {
        guard let offset = cloneOffset ?? cloneSource.map({ _ in .zero }) else { return nil }
        return cloneOffset == nil ? cloneSource : CGPoint(x: point.x + offset.width, y: point.y + offset.height)
    }

    func beginSmudge(id: UUID, at point: CGPoint) {
        guard let image = rawLayerPixels(), let bitmap = PixelOps.bitmap(image) else { return }
        let r = max(1, Int(brushSize / 2))
        var state = SmudgeState(bitmap: bitmap, radius: r, last: point, touched: [UInt8](repeating: 0, count: width * height))
        state.carried = sample(state.bitmap, at: point, radius: r)
        smudgeState = state
        Renderer.transient[id] = image
    }

    /// Pushes the carried paint from the last point to `point` in small steps.
    func smudge(id: UUID, to point: CGPoint) {
        guard var st = smudgeState else { return }
        let dist = hypot(point.x - st.last.x, point.y - st.last.y), step = max(1, Double(st.radius) / 4)
        let n = max(1, Int(dist / step)), keep = 0.55 + 0.44 * max(0, min(1, toolStrength))   // how much paint stays on the brush
        let r = st.radius, side = 2 * r + 1
        for k in 1...n {
            let t = Double(k) / Double(n)
            let c = CGPoint(x: st.last.x + (point.x - st.last.x) * t, y: st.last.y + (point.y - st.last.y) * t)
            let cx = Int(c.x.rounded()), cy = Int(c.y.rounded())
            for dy in -r...r {
                let y = cy + dy; guard y >= 0, y < height else { continue }
                for dx in -r...r {
                    let x = cx + dx; guard x >= 0, x < width else { continue }
                    let d = (Double(dx * dx + dy * dy)).squareRoot() / Double(r); guard d <= 1 else { continue }
                    let w = keep * (1 - d * d)                       // soft edge
                    let ci = ((dy + r) * side + (dx + r)) * 4, pi = st.bitmap.index(x, y)
                    for ch in 0..<4 {
                        let under = Double(st.bitmap.bytes[pi + ch])
                        let mixed = under + (st.carried[ci + ch] - under) * w
                        st.bitmap.bytes[pi + ch] = UInt8(max(0, min(255, mixed.rounded())))
                        st.carried[ci + ch] = st.carried[ci + ch] * keep + mixed * (1 - keep)   // the brush picks up what it passes
                    }
                    st.touched[y * width + x] = 255
                }
            }
        }
        st.last = point
        smudgeState = st
        Renderer.transient[id] = image(of: st.bitmap)
    }

    private func sample(_ b: PixelOps.Bitmap, at p: CGPoint, radius r: Int) -> [Double] {
        let side = 2 * r + 1
        var out = [Double](repeating: 0, count: side * side * 4)
        let cx = Int(p.x.rounded()), cy = Int(p.y.rounded())
        for dy in -r...r { for dx in -r...r {
            let x = min(b.width - 1, max(0, cx + dx)), y = min(b.height - 1, max(0, cy + dy))
            let o = ((dy + r) * side + (dx + r)) * 4, i = b.index(x, y)
            for ch in 0..<4 { out[o + ch] = Double(b.bytes[i + ch]) }
        } }
        return out
    }

    private func image(of b: PixelOps.Bitmap) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(b.bytes) as CFData) else { return nil }
        return CGImage(width: b.width, height: b.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: b.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Turns a finished clone/heal/smudge stroke into a plain bitmap stroke (the live picture is dropped).
    func bakeRetouch(_ stroke: InkStroke) -> InkStroke {
        guard let kind = stroke.kind, ["clone", "heal", "smudge"].contains(kind) else { return stroke }
        defer { Renderer.transient[stroke.id] = nil; if kind == "smudge" { smudgeState = nil } }
        var baked: CGImage?
        if kind == "smudge", let st = smudgeState {
            var b = st.bitmap
            for i in 0..<(width * height) where st.touched[i] == 0 { let p = i * 4; b.bytes[p] = 0; b.bytes[p + 1] = 0; b.bytes[p + 2] = 0; b.bytes[p + 3] = 0 }
            baked = image(of: b)
        } else if let ctx = Renderer.context(width: width, height: height) {
            Renderer.drawStroke(stroke, in: ctx)
            baked = ctx.makeImage()
            if kind == "heal", let copied = baked, let source = Renderer.transient[stroke.id], let target = rawLayerPixels() {
                baked = heal(copied, source: source, target: target, radius: max(4, stroke.width * 0.6)) ?? copied
            }
        }
        guard let baked, let data = PixelOps.png(baked) else { return stroke }
        var out = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: stroke.color, width: 1)
        out.id = stroke.id; out.kind = "bitmap"; out.imageData = data
        out.selectionPoints = stroke.selectionPoints; out.selectionEllipse = stroke.selectionEllipse; out.selectionMask = stroke.selectionMask
        return out
    }

    /// Healing: the source's texture with the target's light and colour,
    /// result = source + blur(target) − blur(source), inside the brushed pixels.
    private func heal(_ copied: CGImage, source: CGImage, target: CGImage, radius: Double) -> CGImage? {
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        func blurred(_ i: CGImage) -> PixelOps.Bitmap? {
            let ci = CIImage(cgImage: i)
            let out = ci.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: ci.extent)
            return context.createCGImage(out, from: ci.extent).flatMap(PixelOps.bitmap)
        }
        guard var c = PixelOps.bitmap(copied), let s = PixelOps.bitmap(source), let bs = blurred(source), let bt = blurred(target) else { return nil }
        for i in 0..<(width * height) {
            let p = i * 4; let a = Int(c.bytes[p + 3]); guard a > 0 else { continue }
            let sa = max(1, Int(s.bytes[p + 3])), ta = max(1, Int(bt.bytes[p + 3])), ba = max(1, Int(bs.bytes[p + 3]))
            for ch in 0..<3 {
                // Unpremultiplied arithmetic, then premultiplied by the brushed alpha again.
                let sv = Double(s.bytes[p + ch]) * 255 / Double(sa), tv = Double(bt.bytes[p + ch]) * 255 / Double(ta), bv = Double(bs.bytes[p + ch]) * 255 / Double(ba)
                let v = max(0, min(255, sv + tv - bv))
                c.bytes[p + ch] = UInt8((v * Double(a) / 255).rounded())
            }
        }
        return image(of: c)
    }
}
