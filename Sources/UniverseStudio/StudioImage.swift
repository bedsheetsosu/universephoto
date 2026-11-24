import CoreGraphics
import SwiftUI

/// Image menu: image size, canvas size, crop, trim, rotate and flip – for the whole document
/// (every layer of every frame) or the active layer – and layer masks from the selection.
/// Geometry changes bake each layer's strokes and transform into pixels (masks too); opacity,
/// blend mode, adjustments, filters, style and clipping stay live.
extension Studio {
    enum ImageDialog: String, Identifiable { case imageSize, canvasSize; var id: String { rawValue } }
    enum Rotation { case clockwise, counterClockwise, halfTurn }

    /// `image` (width × height, y down) drawn through `g` (old pixels → new pixels) on a new canvas.
    static func remap(_ image: CGImage, width: Int, height: Int, _ g: CGAffineTransform, smooth: Bool = true) -> CGImage? {
        guard let ctx = Renderer.context(width: width, height: height) else { return nil }
        ctx.interpolationQuality = smooth ? .high : .none
        ctx.concatenate(g)
        Renderer.drawImage(image, in: ctx, rect: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// The layer with its pixels (and mask) moved through `g` onto a `width` × `height` canvas.
    func baked(_ layer: ArtLayer, width w: Int, height h: Int, _ g: CGAffineTransform) -> ArtLayer {
        var content = layer
        content.opacity = 1; content.blend = .normal; content.visible = true; content.adjustment = .init()
        content.filters = nil; content.mask = nil; content.clipped = false; content.style = nil
        // Rendered without its transform and moved in one go, so parts pushed off the canvas survive
        // a bigger canvas (Reveal all, Canvas size) instead of being cut at the old edge.
        content.transform = .init()
        let placement = matrix(layer.transform).concatenating(g)
        var out = layer
        out.transform = .init()
        if let image = Renderer.render(layers: [content], width: width, height: height),
           let moved = Self.remap(image, width: w, height: h, placement), let data = try? Renderer.png(moved) {
            out.imageData = data; out.strokes = []
        }
        if let mask = layer.mask, !mask.isEmpty {
            // The mask lives in layer coordinates: place it like the layer, then move it.
            var matte = ArtLayer(name: "mask")
            var white = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1); white.kind = "fill"
            matte.strokes = [white] + mask
            if let m = Renderer.render(layers: [matte], width: width, height: height) {
                out.mask = Self.maskStrokes(Self.remap(m, width: w, height: h, placement), width: w, height: h)
            }
        }
        return out
    }

    /// A mask made of one picture (drawn over the white base; what lies outside it stays visible).
    static func maskStrokes(_ image: CGImage?, width: Int, height: Int) -> [InkStroke] {
        guard let image, let data = try? Renderer.png(image) else { return [] }
        var s = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1)
        s.kind = "bitmap"; s.imageData = data
        return [s]
    }

    /// Applies `g` to every layer of every frame and gives the document its new size.
    func transformDocument(_ label: String, width w: Int, height h: Int, _ g: CGAffineTransform) {
        guard (1...16384).contains(w), (1...16384).contains(h), w * h <= 100_000_000, !isPlaying else { return }
        checkpoint(label)
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        frames = frames.map { $0.map { baked($0, width: w, height: h, g) } }
        layers = layers.map { baked($0, width: w, height: h, g) }
        // Guides follow the picture (a quarter turn makes vertical guides horizontal).
        guides = guides.compactMap { guide in
            let a = (guide.vertical ? CGPoint(x: guide.position, y: 0) : CGPoint(x: 0, y: guide.position)).applying(g)
            let b = (guide.vertical ? CGPoint(x: guide.position, y: 1) : CGPoint(x: 1, y: guide.position)).applying(g)
            let vertical = abs(a.x - b.x) < 0.001, pos = vertical ? a.x : a.y
            return pos < 0 || pos > Double(vertical ? w : h) ? nil : Guide(id: guide.id, vertical: vertical, position: pos.rounded())
        }
        width = w; height = h
        selection = nil; boundsCache.removeAll()
        changed()
    }

    func resizeImage(width w: Int, height h: Int) {
        transformDocument("Image size", width: w, height: h, CGAffineTransform(scaleX: Double(w) / Double(width), y: Double(h) / Double(height)))
    }

    /// New canvas size; `anchor` (0…1 per axis) says where the old picture sits.
    func resizeCanvas(width w: Int, height h: Int, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        let dx = (Double(w - width) * anchor.x).rounded(), dy = (Double(h - height) * anchor.y).rounded()
        transformDocument("Canvas size", width: w, height: h, CGAffineTransform(translationX: dx, y: dy))
    }

    /// Image → Reveal all: grows the canvas until every layer's content (also what was moved or
    /// scaled past the edge) fits. Returns false when everything is already inside.
    @discardableResult func revealAll() -> Bool {
        guard let r = revealAllRect() else { return false }
        transformDocument("Reveal all", width: Int(r.width), height: Int(r.height), CGAffineTransform(translationX: -r.minX, y: -r.minY))
        return true
    }

    /// The canvas grown to every layer's content, in document pixels; nil when nothing sticks out.
    func revealAllRect() -> CGRect? {
        var r = CGRect(x: 0, y: 0, width: width, height: height)
        for layer in frames.flatMap({ $0 }) + layers where !layer.isAdjustmentLayer && layer.transform != LayerTransform() {
            guard let box = contentBounds(layer) else { continue }
            r = r.union(box.applying(matrix(layer.transform)))
        }
        r = r.integral
        return r == CGRect(x: 0, y: 0, width: width, height: height) ? nil : r
    }

    func crop(to rect: CGRect) {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !r.isEmpty, r.size != CGSize(width: width, height: height) else { return }
        transformDocument("Crop", width: Int(r.width), height: Int(r.height), CGAffineTransform(translationX: -r.minX, y: -r.minY))
    }

    func cropToSelection() { if let sel = selection { crop(to: sel.bounds) } }

    /// Crops away the transparent border around everything visible.
    func trim() {
        guard let image = Renderer.render(layers: composite(layers), width: width, height: height), let b = PixelOps.bitmap(image) else { return }
        var alpha = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) { alpha[i] = b.bytes[i * 4 + 3] }
        if let box = PixelOps.bounds(alpha, width: width, height: height) { crop(to: box) }
    }

    func rotateCanvas(_ r: Rotation) {
        let w = Double(width), h = Double(height)
        switch r {
        case .clockwise: transformDocument("Rotate canvas", width: height, height: width, CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0))
        case .counterClockwise: transformDocument("Rotate canvas", width: height, height: width, CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))
        case .halfTurn: transformDocument("Rotate canvas", width: width, height: height, CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h))
        }
    }

    static func flip(horizontal: Bool, width: Int, height: Int) -> CGAffineTransform {
        horizontal ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: Double(width), ty: 0) : CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: Double(height))
    }

    func flipCanvas(horizontal: Bool) {
        transformDocument("Flip canvas", width: width, height: height, Self.flip(horizontal: horizontal, width: width, height: height))
    }

    func flipLayer(horizontal: Bool) {
        guard canEdit, let layer = activeLayer else { return }
        let flipped = baked(layer, width: width, height: height, Self.flip(horizontal: horizontal, width: width, height: height))
        mutateLayer("Flip layer") { $0 = flipped }
        boundsCache.removeAll()
    }

    /// Layer mask from the selection: `reveal` shows only the selection, otherwise hides it.
    func maskFromSelection(reveal: Bool) {
        guard let layer = activeLayer, !layer.locked, let sel = selectionMask(),
              let shape = PixelOps.fillImage(reveal ? sel : sel.map { 255 - $0 }, width: width, height: height, color: .white) else { return }
        // Selection is in document pixels, the mask in layer pixels: undo the layer's transform.
        let local = Self.remap(shape, width: width, height: height, matrix(layer.transform).inverted()) ?? shape
        var black = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), width: 1)
        black.kind = "fill"
        let strokes = [black] + Self.maskStrokes(local, width: width, height: height)
        mutateLayer(reveal ? "Reveal selection" : "Hide selection") { $0.mask = strokes }
        maskEditing = false
    }
}

/// Image size and canvas size, with linked proportions and a nine-point anchor.
struct ImageSizeDialog: View {
    @EnvironmentObject private var s: Studio
    @Environment(\.photoTheme) private var theme
    var kind: Studio.ImageDialog
    @State private var w = 0
    @State private var h = 0
    @State private var linked = true
    @State private var anchor = CGPoint(x: 0.5, y: 0.5)

    private var valid: Bool { (1...16384).contains(w) && (1...16384).contains(h) && w * h <= 100_000_000 && (w != s.width || h != s.height) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L(kind == .imageSize ? "Image size" : "Canvas size")).font(.system(size: 23, weight: .bold, design: .rounded))
            Text(LF("Now %d × %d px", s.width, s.height)).font(.caption).foregroundStyle(theme.secondary)
            HStack {
                Text(L("Width")); TextField("px", value: Binding(get: { w }, set: { v in w = v; if linked { h = max(1, Int((Double(v) * Double(s.height) / Double(s.width)).rounded())) } }), format: .number).accessibilityLabel(L("Width"))
                Button { linked.toggle() } label: { Image(systemName: linked ? "link" : "link.badge.plus") }.buttonStyle(PhotoPress())
                    .help(L("Keep proportions")).accessibilityLabel(L("Keep proportions")).accessibilityAddTraits(linked ? .isSelected : [])
                Text(L("Height")); TextField("px", value: Binding(get: { h }, set: { v in h = v; if linked { w = max(1, Int((Double(v) * Double(s.width) / Double(s.height)).rounded())) } }), format: .number).accessibilityLabel(L("Height"))
            }.textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                ForEach([50, 200], id: \.self) { p in
                    Button("\(p) %") { w = max(1, s.width * p / 100); h = max(1, s.height * p / 100) }
                }
            }.buttonStyle(PhotoButtonStyle())
            if kind == .canvasSize {
                HStack(alignment: .top, spacing: 14) {
                    Text(L("Anchor")).font(.system(size: 11)).foregroundStyle(theme.secondary)
                    Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                        ForEach([0.0, 0.5, 1.0], id: \.self) { y in
                            GridRow {
                                ForEach([0.0, 0.5, 1.0], id: \.self) { x in
                                    let on = anchor == CGPoint(x: x, y: y)
                                    Button { anchor = CGPoint(x: x, y: y) } label: {
                                        RoundedRectangle(cornerRadius: 4).fill(on ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.card)).frame(width: 20, height: 20)
                                    }.buttonStyle(PhotoPress()).accessibilityLabel(L("Anchor")).accessibilityAddTraits(on ? .isSelected : [])
                                }
                            }
                        }
                    }
                }
            } else {
                Text(L("Strokes and text are turned into pixels.")).font(.caption).foregroundStyle(theme.secondary)
            }
            HStack {
                Button(L("Cancel")) { s.imageDialog = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Apply")) {
                    if kind == .imageSize { s.resizeImage(width: w, height: h) } else { s.resizeCanvas(width: w, height: h, anchor: anchor) }
                    s.imageDialog = nil
                }.buttonStyle(PhotoButtonStyle(prominent: true)).keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }
        .padding(28).frame(width: 460).background(PhotoAmbient())
        .onAppear { w = s.width; h = s.height; linked = kind == .imageSize }
    }
}
