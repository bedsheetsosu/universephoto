import AppKit
import CoreGraphics
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// A canvas-owned cache. It is deliberately non-Sendable; do not share between render queues.
/// At most 64 MiB of isolated layer bitmaps is retained, and preview strokes are never cached.
final class LayerImageCache {
    private struct Entry { var layer: ArtLayer; var image: CGImage; var width: Int; var height: Int }
    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []
    private var bytes = 0
    private let budget = 64 * 1024 * 1024
    func image(for layer: ArtLayer, width: Int, height: Int) -> CGImage? {
        guard let e = entries[layer.id], e.layer == bitmapKey(layer), e.width == width, e.height == height else { return nil }
        return e.image
    }
    func store(_ image: CGImage, layer: ArtLayer, width: Int, height: Int) {
        if let old = entries.removeValue(forKey:layer.id) { bytes -= old.width * old.height * 4; order.removeAll { $0 == layer.id } }
        let required = width * height * 4
        guard required <= budget else { return }
        while bytes + required > budget, let oldest = order.first {
            order.removeFirst()
            if let removed = entries.removeValue(forKey:oldest) { bytes -= removed.width * removed.height * 4 }
        }
        entries[layer.id] = Entry(layer:bitmapKey(layer),image:image,width:width,height:height); order.append(layer.id); bytes += required
    }
    private func bitmapKey(_ layer: ArtLayer) -> ArtLayer {
        var key = layer
        key.name = ""; key.visible = true; key.opacity = 1; key.blend = .normal; key.locked = false; key.transform = .init()
        return key
    }
    func retain(ids: Set<UUID>) {
        for id in order where !ids.contains(id) {
            if let removed = entries.removeValue(forKey:id) { bytes -= removed.width * removed.height * 4 }
        }
        order.removeAll { !ids.contains($0) }
    }
}

/// CPU reference compositor. Every public coordinate is in document pixels with y=0 at the top.
/// All scratch contexts are flipped once; compositing cancels that flip when drawing CGImages.
enum Renderer {
    /// Pictures of retouch strokes still being drawn (main thread only; baked on release).
    nonisolated(unsafe) static var transient: [UUID: CGImage] = [:]
    // CIContext is reusable and documented as thread-safe; retain its internal pipeline caches.
    private static let filters = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    enum RenderError: LocalizedError {
        case encoding
        var errorDescription: String? { "Das Bild konnte nicht kodiert werden." }
    }
    static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, width <= 16384, height <= 16384,
              width * height <= 100_000_000 else { return nil }
        guard let result = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                         bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        result.translateBy(x: 0, y: CGFloat(height)); result.scaleBy(x: 1, y: -1)
        return result
    }
    static func render(layers: [ArtLayer], width: Int, height: Int,
                       preview: InkStroke? = nil, previewLayer: Int? = nil, cache: LayerImageCache? = nil) -> CGImage? {
        guard let result = context(width: width, height: height) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        // Clipping: a clipped layer only shows where the nearest unclipped layer below has pixels.
        var base: CGImage?           // that layer, placed (transform applied), when something clips to it
        var baseShown = true         // a hidden base hides what clips to it
        var hasBase = false
        for (index, layer) in layers.enumerated() {
            let clipping = layer.clipped && hasBase
            if !clipping { base = nil; hasBase = true; baseShown = layer.visible && layer.opacity > 0 }
            guard layer.visible && layer.opacity > 0, !clipping || (baseShown && base != nil) else { continue }
            let hasPreview = index == previewLayer && preview != nil
            let layerImage: CGImage?
            if !hasPreview, let cached = cache?.image(for:layer,width:width,height:height) { layerImage = cached }
            else {
                let reuse = hasPreview && layer.mask == nil && layer.adjustment == LayerAdjustment() ? cache?.image(for:layer,width:width,height:height) : nil
                layerImage = renderLayer(layer, width:width,height:height,preview:hasPreview ? preview : nil, base:reuse)
                if !hasPreview, let layerImage { cache?.store(layerImage,layer:layer,width:width,height:height) }
            }
            guard let image = layerImage else { continue }
            let clipsNext = layers.indices.contains(index + 1) && layers[index + 1].clipped
            let styled = layer.style?.isActive == true
            if clipping || clipsNext || styled {
                guard let placedImage = placed(image, transform: layer.transform, width: width, height: height) else { continue }
                if clipsNext && !clipping { base = placedImage }
                var shown = styled ? (applyStyle(layer.style!, to: placedImage) ?? placedImage) : placedImage
                if clipping, let base, let ctx = context(width: width, height: height) {
                    drawImage(placedImage, in: ctx, rect: bounds)
                    ctx.setBlendMode(.destinationIn); drawImage(base, in: ctx, rect: bounds)
                    shown = ctx.makeImage() ?? placedImage
                }
                result.saveGState()
                result.setAlpha(max(0, min(1, layer.opacity))); result.setBlendMode(blendMode(layer.blend))
                drawImage(shown, in: result, rect: bounds)
                result.restoreGState()
                continue
            }
            result.saveGState()
            result.setAlpha(max(0, min(1, layer.opacity)))
            result.setBlendMode(blendMode(layer.blend))
            // Layer pivot is the document center. Translation remains in document pixels.
            apply(layer.transform, to: result, width: width, height: height)
            drawImage(image, in: result, rect: bounds)
            result.restoreGState()
        }
        cache?.retain(ids: Set(layers.map(\.id)))
        return result.makeImage()
    }
    static func apply(_ t: LayerTransform, to ctx: CGContext, width: Int, height: Int) {
        ctx.translateBy(x: t.x + Double(width)/2, y: t.y + Double(height)/2)
        ctx.rotate(by: t.rotation * .pi / 180)
        ctx.scaleBy(x: t.scale, y: t.scale)
        ctx.translateBy(x: -Double(width)/2, y: -Double(height)/2)
    }
    /// The layer picture with its transform applied, in document pixels.
    static func placed(_ image: CGImage, transform: LayerTransform, width: Int, height: Int) -> CGImage? {
        if transform == LayerTransform() { return image }
        guard let ctx = context(width: width, height: height) else { return nil }
        apply(transform, to: ctx, width: width, height: height)
        drawImage(image, in: ctx, rect: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
    /// Layer effects on a placed layer picture: glow and shadow below, outline around, overlay on top.
    static func applyStyle(_ style: LayerStyle, to image: CGImage) -> CGImage? {
        let w = image.width, h = image.height, r = CGRect(x: 0, y: 0, width: w, height: h)
        guard let ctx = context(width: w, height: h) else { return nil }
        // Only the shadow of a picture: draw it far off to the left, its shadow shifted back in.
        func shadowOnly(color: CodableColor, opacity: Double, offset: CGSize, blur: Double) {
            var c = color; c.alpha = max(0, min(1, opacity))
            ctx.saveGState()
            let far = Double(w) * 2 + blur * 4
            // Shadow offsets live in device space (y up), the context draws y down.
            ctx.setShadow(offset: CGSize(width: far + offset.width, height: -offset.height), blur: blur, color: c.cgColor)
            drawImage(image, in: ctx, rect: r.offsetBy(dx: -far, dy: 0))
            ctx.restoreGState()
        }
        if style.glow.on { shadowOnly(color: style.glow.color, opacity: style.glow.opacity, offset: .zero, blur: style.glow.size) }
        if style.shadow.on {
            let a = style.shadow.angle * .pi / 180
            // Light comes from `angle` (0° = right, 90° = top); the shadow falls the other way.
            shadowOnly(color: style.shadow.color, opacity: style.shadow.opacity,
                       offset: CGSize(width: -cos(a) * style.shadow.distance, height: sin(a) * style.shadow.distance), blur: style.shadow.blur)
        }
        if style.outline.on, style.outline.width > 0 {
            // Outside stroke: the alpha grown by the width, filled with the colour, under the picture.
            let alpha = CIImage(cgImage: image).applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: style.outline.width])
            var c = style.outline.color; c.alpha = max(0, min(1, style.outline.opacity))
            let fill = CIImage(color: CIColor(cgColor: c.cgColor)).cropped(to: CIImage(cgImage: image).extent)
            let outline = fill.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: fill.extent), kCIInputMaskImageKey: alpha])
            if let cg = filters.createCGImage(outline, from: fill.extent) { drawImage(cg, in: ctx, rect: r) }
        }
        drawImage(image, in: ctx, rect: r)
        if style.overlay.on {
            ctx.saveGState()
            ctx.setBlendMode(.sourceAtop)
            var c = style.overlay.color; c.alpha = max(0, min(1, style.overlay.opacity))
            ctx.setFillColor(c.cgColor); ctx.fill(r)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
    private static func renderLayer(_ layer: ArtLayer, width: Int, height: Int, preview: InkStroke?, base: CGImage? = nil) -> CGImage? {
        guard let bitmap = context(width:width,height:height) else { return nil }
        if let base { drawImage(base,in:bitmap,rect:CGRect(x:0,y:0,width:width,height:height)) }
        else {
        if let data = layer.imageData, let source = CGImageSourceCreateWithData(data as CFData,nil), let image = CGImageSourceCreateImageAtIndex(source,0,nil) {
            drawImage(image,in:bitmap,rect:CGRect(x:0,y:0,width:width,height:height))
        }
        for stroke in layer.strokes { drawStroke(stroke,in:bitmap) }
        }
        if let preview { drawStroke(preview,in:bitmap) }
        guard var image = bitmap.makeImage() else { return nil }
        if let mask = layer.mask { image = applyMask(mask,image:image,width:width,height:height) ?? image }
        image = adjusted(image,adjustment:layer.adjustment) ?? image
        return filtered(image,layer.filters ?? []) ?? image
    }
    /// The layer's smart filter stack (enabled entries, in order).
    static func filtered(_ image: CGImage, _ stack: [SmartFilter]) -> CGImage? {
        let active = stack.filter(\.enabled)
        guard !active.isEmpty else { return image }
        let input = CIImage(cgImage: image)
        let output = active.reduce(input) { $1.apply(to: $0) }
        return filters.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    static func drawImage(_ image: CGImage, in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
    static func blendMode(_ blend: LayerBlend) -> CGBlendMode {
        switch blend { case .normal: .normal; case .multiply: .multiply; case .screen: .screen
        case .overlay: .overlay; case .darken: .darken; case .lighten: .lighten
        case .colorBurn: .colorBurn; case .linearBurn: .plusDarker; case .colorDodge: .colorDodge; case .linearDodge: .plusLighter
        case .softLight: .softLight; case .hardLight: .hardLight; case .difference: .difference; case .exclusion: .exclusion
        case .hue: .hue; case .saturation: .saturation; case .color: .color; case .luminosity: .luminosity }
    }
    static func drawStroke(_ stroke: InkStroke, in context: CGContext) {
        guard let first = stroke.points.first, first.x.isFinite, first.y.isFinite, stroke.width.isFinite, stroke.width > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if let maskData = stroke.selectionMask, let mask = PixelOps.decodeGray(maskData) {
            // The context is flipped (y down); flip once for the mask, then flip back. The clip stays.
            let h = CGFloat(mask.height)
            context.translateBy(x: 0, y: h); context.scaleBy(x: 1, y: -1)
            context.clip(to: CGRect(x: 0, y: 0, width: mask.width, height: mask.height), mask: mask)
            context.scaleBy(x: 1, y: -1); context.translateBy(x: 0, y: -h)
        } else if let points = stroke.selectionPoints, let start = points.first, points.count >= 2 {
            let path = CGMutablePath()
            if points.count == 2 {
                let end = points[1]
                let bounds = CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: abs(end.x-start.x), height: abs(end.y-start.y))
                if stroke.selectionEllipse == true { path.addEllipse(in: bounds) } else { path.addRect(bounds) }
            } else {
                path.move(to: CGPoint(x:start.x,y:start.y))
                for point in points.dropFirst() { path.addLine(to:CGPoint(x:point.x,y:point.y)) }
                path.closeSubpath()
            }
            context.addPath(path); context.clip()
        }
        context.setBlendMode(stroke.isEraser ? .clear : .normal)
        context.setStrokeColor(stroke.color.cgColor)
        context.setFillColor(stroke.color.cgColor)
        context.setLineCap(.round); context.setLineJoin(.round)
        context.setLineWidth(max(0.1, stroke.width))
        let p = CGPoint(x: first.x, y: first.y)
        let last = stroke.points.last ?? first
        let q = CGPoint(x: last.x, y: last.y)
        let rect = CGRect(x: min(p.x,q.x), y: min(p.y,q.y), width: abs(q.x-p.x), height: abs(q.y-p.y))
        switch stroke.kind {
        case "rectangle", "ellipse", "roundedRect", "polygon", "star":
            if let shape = ShapeGeometry.path(kind: stroke.kind!, in: rect, parameter: stroke.strength) {
                context.addPath(shape)
                if stroke.filled == true { context.fillPath() } else { context.strokePath() }
            }
        case "line": context.move(to: p); context.addLine(to: q); context.strokePath()
        case "arrow":
            let w = max(0.1, stroke.width), a = atan2(q.y - p.y, q.x - p.x), back = max(12, w * 3.2) * 0.7
            context.move(to: p); context.addLine(to: CGPoint(x: q.x - cos(a) * back, y: q.y - sin(a) * back)); context.strokePath()
            context.addPath(ShapeGeometry.arrowHead(from: p, to: q, width: w)); context.fillPath()
        case "fill": context.fill(context.boundingBoxOfClipPath)
        case "bitmap":
            if let data = stroke.imageData, let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                drawImage(image, in: context, rect: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
        case "gradient", "gradientRadial", "gradientReflected":
            let a = stroke.color.cgColor, b = (stroke.secondaryColor ?? .white).cgColor, space = CGColorSpace(name: CGColorSpace.sRGB)
            let both: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            switch stroke.kind {
            case "gradientRadial":
                if let g = CGGradient(colorsSpace: space, colors: [a, b] as CFArray, locations: [0, 1]) {
                    context.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: max(1, hypot(q.x - p.x, q.y - p.y)), options: both)
                }
            case "gradientReflected":
                // Start colour on the drag's start, the second colour on both ends of the mirrored line.
                if let g = CGGradient(colorsSpace: space, colors: [b, a, b] as CFArray, locations: [0, 0.5, 1]) {
                    context.drawLinearGradient(g, start: CGPoint(x: 2 * p.x - q.x, y: 2 * p.y - q.y), end: q, options: both)
                }
            default:
                if let g = CGGradient(colorsSpace: space, colors: [a, b] as CFArray, locations: [0, 1]) {
                    context.drawLinearGradient(g, start: p, end: q, options: both)
                }
            }
        case "text":
            let font = CTFontCreateWithName((stroke.fontName ?? "Helvetica") as CFString, max(6, stroke.width), nil)
            let attr: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): stroke.color.cgColor]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: stroke.text ?? "", attributes: attr))
            context.translateBy(x: p.x, y: p.y + max(6, stroke.width))
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(line, context)
        case "dodge", "burn":
            // Soft light with white/black lightens/darkens; then the old transparency is restored.
            guard let before = context.makeImage() else { break }
            let strength = max(0, min(1, stroke.strength ?? 0.5))
            context.setBlendMode(.softLight)
            context.setFillColor(CGColor(gray: stroke.kind == "dodge" ? 1 : 0, alpha: strength))
            context.addPath(brushPath(stroke)); context.fillPath()
            context.setBlendMode(.destinationIn)
            drawImage(before, in: context, rect: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        case "blurBrush", "sharpenBrush":
            guard let before = context.makeImage() else { break }
            let strength = max(0, min(1, stroke.strength ?? 0.5)), input = CIImage(cgImage: before)
            let output = stroke.kind == "blurBrush"
                ? input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1 + strength * 9]).cropped(to: input.extent)
                : input.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: strength * 2, kCIInputRadiusKey: 2.5])
            guard let filtered = filters.createCGImage(output, from: input.extent) else { break }
            context.addPath(brushPath(stroke)); context.clip()
            context.setBlendMode(.copy)
            drawImage(filtered, in: context, rect: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        case "clone", "heal", "smudge":
            // Live retouch: the studio keeps the picture to show (shifted source or smudged pixels);
            // on release the stroke is baked into a bitmap stroke.
            guard let picture = transient[stroke.id] else { break }
            if stroke.kind == "smudge" { context.setBlendMode(.copy) } else { context.addPath(brushPath(stroke)); context.clip() }
            drawImage(picture, in: context, rect: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        default: drawBrush(stroke, in: context)
        }
    }
    private static func drawBrush(_ stroke: InkStroke, in context: CGContext) {
        context.addPath(brushPath(stroke)); context.fillPath()
    }
    /// The filled outline of a pressure brush stroke (also the clip of the retouch brushes).
    static func brushPath(_ stroke: InkStroke) -> CGPath {
        // One filled silhouette gives constant opacity at overlapping joints. Segment quads
        // connect the pressure radii directly; only real samples add round/elliptical joins.
        // This avoids thousands of overlapping interpolated ellipses on a long stroke.
        let silhouette = CGMutablePath()
        let points = stroke.points.filter { $0.x.isFinite && $0.y.isFinite }
        func radius(_ p: InkPoint) -> Double { max(0.15, stroke.width * max(0.05, min(1, p.pressure.isFinite ? p.pressure : 1)) / 2) }
        func tip(_ p: InkPoint) -> (Double,Double) {
            let tx = p.tiltX ?? 0, ty = p.tiltY ?? 0
            let tilt = tx.isFinite && ty.isFinite ? min(1,hypot(tx,ty)) : 0
            let roll = p.rotation ?? 0
            return (max(0.3,1-tilt*0.6),roll.isFinite ? roll * .pi/180 : 0)
        }
        func support(_ p: InkPoint, nx: Double, ny: Double) -> Double {
            let (aspect,angle) = tip(p)
            let x = nx*cos(angle)+ny*sin(angle), y = -nx*sin(angle)+ny*cos(angle)
            return radius(p)*sqrt(x*x+aspect*aspect*y*y)
        }
        for p in points {
            let r = radius(p), (aspect,angle) = tip(p)
            var transform = CGAffineTransform(translationX:p.x,y:p.y).rotated(by:angle).scaledBy(x:1,y:aspect)
            let circle = CGMutablePath()
            circle.addArc(center:.zero,radius:r,startAngle:0,endAngle:2 * .pi,clockwise:false)
            circle.closeSubpath()
            if let ellipse = circle.copy(using:&transform) { silhouette.addPath(ellipse) }
        }
        for (a,b) in zip(points,points.dropFirst()) {
            let dx = b.x-a.x, dy = b.y-a.y, length = hypot(dx,dy)
            guard length > 0.0001 else { continue }
            let nx = -dy/length, ny = dx/length
            let ra = support(a,nx:nx,ny:ny), rb = support(b,nx:nx,ny:ny)
            silhouette.move(to:CGPoint(x:a.x+nx*ra,y:a.y+ny*ra))
            silhouette.addLine(to:CGPoint(x:a.x-nx*ra,y:a.y-ny*ra))
            silhouette.addLine(to:CGPoint(x:b.x-nx*rb,y:b.y-ny*rb))
            silhouette.addLine(to:CGPoint(x:b.x+nx*rb,y:b.y+ny*rb))
            silhouette.closeSubpath()
        }
        return silhouette
    }
    private static func applyMask(_ strokes: [InkStroke], image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let mask = context(width: width, height: height) else { return nil }
        mask.setFillColor(CGColor(gray: 1, alpha: 1)); mask.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for stroke in strokes { drawStroke(stroke, in: mask) }
        guard let maskImage = mask.makeImage() else { return nil }
        let input = CIImage(cgImage: image), matte = CIImage(cgImage: maskImage)
        let transparent = CIImage(color: .clear).cropped(to: input.extent)
        let output = input.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: transparent, kCIInputMaskImageKey: matte])
        return filters.createCGImage(output, from: input.extent)
    }
    static func adjusted(_ image: CGImage, adjustment a: LayerAdjustment) -> CGImage? {
        guard a != LayerAdjustment() else { return image }
        let input = CIImage(cgImage: image)
        let extent = input.extent
        var output = input
        if a.brightness != 0 || a.contrast != 1 || a.saturation != 1 {
            output = output.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: a.brightness,
                kCIInputContrastKey: a.contrast, kCIInputSaturationKey: a.saturation])
        }
        if a.exposure != 0 { output = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: a.exposure]) }
        // Levels: input black/white points as a linear stretch, then gamma for the midtones.
        if a.levelsBlack != 0 || a.levelsWhite != 1 {
            let lo = min(a.levelsBlack, a.levelsWhite - 0.01), scale = 1 / max(0.01, a.levelsWhite - lo)
            let v = CIVector(x: scale, y: 0, z: 0, w: 0)
            output = output.applyingFilter("CIColorMatrix", parameters: ["inputRVector": v, "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0), "inputBiasVector": CIVector(x: -lo * scale, y: -lo * scale, z: -lo * scale, w: 0)])
                .applyingFilter("CIColorClamp")
        }
        if a.gamma != 1 { output = output.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 1 / max(0.05, a.gamma)]) }
        if let curves = a.curves, let table = ToneCurve.table(curves) {
            output = output.applyingFilter("CIColorCurves", parameters: ["inputCurvesData": table, "inputCurvesDomain": CIVector(x: 0, y: 1),
                "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!])
        }
        if a.hue != 0 { output = output.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: a.hue * .pi / 180]) }
        if a.vibrance != 0 { output = output.applyingFilter("CIVibrance", parameters: ["inputAmount": a.vibrance]) }
        if a.temperature != 0 || a.tint != 0 {
            output = output.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 - a.temperature * 3000, y: a.tint * 100)])
        }
        if a.noiseReduction > 0 { output = output.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": a.noiseReduction * 0.1, "inputSharpness": 0.4]) }
        if a.sharpen > 0 { output = output.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: a.sharpen, kCIInputRadiusKey: 2.5]) }
        if a.posterize >= 2 { output = output.applyingFilter("CIColorPosterize", parameters: ["inputLevels": a.posterize]) }
        if a.pixelate >= 2 {
            output = output.clampedToExtent().applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: a.pixelate, kCIInputCenterKey: CIVector(x: 0, y: 0)]).cropped(to: extent)
        }
        if a.inverted { output = output.applyingFilter("CIColorInvert") }
        if a.blur > 0 { output = output.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: a.blur]).cropped(to: extent) }
        if a.vignette > 0 {
            output = output.applyingFilter("CIVignetteEffect", parameters: [kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                kCIInputRadiusKey: max(extent.width, extent.height) * 0.62, kCIInputIntensityKey: a.vignette, "inputFalloff": 0.6])
        }
        if a.grain > 0, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage {
            // Monochrome grain, centred on grey, mixed in with soft light so it keeps the tones.
            let grain = noise.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: a.grain * 0.5)])
                .cropped(to: extent)
            output = grain.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: output])
            // Keep the layer's own transparency.
            output = output.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent), kCIInputMaskImageKey: input])
        }
        return filters.createCGImage(output, from: extent)
    }
    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw RenderError.encoding }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.encoding }
        return data as Data
    }
    static func sample(_ image: CGImage, at point: CGPoint) -> CodableColor {
        guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
              point.x < Double(image.width), point.y < Double(image.height) else { return CodableColor(red: 0, green: 0, blue: 0, alpha: 0) }
        let x = Int(floor(point.x)), y = Int(floor(point.y))
        guard x >= 0, x < image.width, y >= 0, y < image.height,
              let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let ctx = context(width: 1, height: 1) else { return CodableColor(red: 0, green: 0, blue: 0, alpha: 0) }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return .black }
        let a = Double(bytes[3])/255
        guard a > 0 else { return CodableColor(red: 0, green: 0, blue: 0, alpha: 0) }
        return CodableColor(red: min(1,Double(bytes[0])/255/a), green: min(1,Double(bytes[1])/255/a), blue: min(1,Double(bytes[2])/255/a), alpha: a)
    }
}
