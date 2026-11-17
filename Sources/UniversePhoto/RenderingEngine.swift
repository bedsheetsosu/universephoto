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
        for (index, layer) in layers.enumerated() where layer.visible && layer.opacity > 0 {
            let hasPreview = index == previewLayer && preview != nil
            let layerImage: CGImage?
            if !hasPreview, let cached = cache?.image(for:layer,width:width,height:height) { layerImage = cached }
            else {
                let base = hasPreview && layer.mask == nil && layer.adjustment == LayerAdjustment() ? cache?.image(for:layer,width:width,height:height) : nil
                layerImage = renderLayer(layer, width:width,height:height,preview:hasPreview ? preview : nil, base:base)
                if !hasPreview, let layerImage { cache?.store(layerImage,layer:layer,width:width,height:height) }
            }
            guard let image = layerImage else { continue }
            result.saveGState()
            result.setAlpha(max(0, min(1, layer.opacity)))
            result.setBlendMode(blendMode(layer.blend))
            // Layer pivot is the document center. Translation remains in document pixels.
            let t = layer.transform
            result.translateBy(x: t.x + Double(width)/2, y: t.y + Double(height)/2)
            result.rotate(by: t.rotation * .pi / 180)
            result.scaleBy(x: t.scale, y: t.scale)
            result.translateBy(x: -Double(width)/2, y: -Double(height)/2)
            drawImage(image, in: result, rect: bounds)
            result.restoreGState()
        }
        cache?.retain(ids: Set(layers.map(\.id)))
        return result.makeImage()
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
        return adjusted(image,adjustment:layer.adjustment) ?? image
    }
    private static func drawImage(_ image: CGImage, in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
    static func blendMode(_ blend: LayerBlend) -> CGBlendMode {
        switch blend { case .normal: .normal; case .multiply: .multiply; case .screen: .screen
        case .overlay: .overlay; case .darken: .darken; case .lighten: .lighten }
    }
    static func drawStroke(_ stroke: InkStroke, in context: CGContext) {
        guard let first = stroke.points.first, first.x.isFinite, first.y.isFinite, stroke.width.isFinite, stroke.width > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if let points = stroke.selectionPoints, let start = points.first, points.count >= 2 {
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
        case "rectangle": context.stroke(rect)
        case "ellipse": context.strokeEllipse(in: rect)
        case "line": context.move(to: p); context.addLine(to: q); context.strokePath()
        case "fill": context.fill(context.boundingBoxOfClipPath)
        case "gradient":
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                         colors: [stroke.color.cgColor, (stroke.secondaryColor ?? .white).cgColor] as CFArray,
                                         locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: p, end: q, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        case "text":
            let font = CTFontCreateWithName("Helvetica" as CFString, max(6, stroke.width), nil)
            let attr: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): stroke.color.cgColor]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: stroke.text ?? "", attributes: attr))
            context.translateBy(x: p.x, y: p.y + max(6, stroke.width))
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(line, context)
        default: drawBrush(stroke, in: context)
        }
    }
    private static func drawBrush(_ stroke: InkStroke, in context: CGContext) {
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
        context.addPath(silhouette); context.fillPath()
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
    private static func adjusted(_ image: CGImage, adjustment: LayerAdjustment) -> CGImage? {
        guard adjustment != LayerAdjustment() else { return image }
        let input = CIImage(cgImage: image)
        var output = input.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: adjustment.brightness,
            kCIInputContrastKey: adjustment.contrast, kCIInputSaturationKey: adjustment.saturation])
        if adjustment.exposure != 0 { output = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: adjustment.exposure]) }
        if adjustment.inverted { output = output.applyingFilter("CIColorInvert") }
        if adjustment.blur > 0 { output = output.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: adjustment.blur]).cropped(to: input.extent) }
        return filters.createCGImage(output, from: input.extent)
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
