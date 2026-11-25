import AppKit
import SwiftUI

struct ArtworkCanvas: NSViewRepresentable {
    @ObservedObject var studio: Studio
    var grid: Bool; var rulers: Bool; var snap: Bool; var background:NSColor = .windowBackgroundColor; var motionPath = false
    func makeNSView(context: Context) -> ArtworkView { let v = ArtworkView(); v.clipsToBounds = true; v.studio = studio; DispatchQueue.main.async { if v.bounds.size != .zero { studio.canvasViewSize = v.bounds.size } }; return v }
    func updateNSView(_ view: ArtworkView, context: Context) { view.studio = studio;view.backdrop = background; view.grid = grid; view.rulers = rulers; view.snap = snap; view.motionPath = motionPath; view.needsDisplay = true; studio.pen.onPen = { [weak view] sample in view?.remote(sample) }; studio.liquifyChanged = { [weak view] in view?.needsDisplay = true } }
}

@MainActor final class ArtworkView: NSView {
    weak var studio: Studio?
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Published once the size has settled: during an animated layout change (focus mode, timeline)
        // a per-frame update would re-render the whole workspace every frame.
        sizeSettle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let s = self.studio, s.canvasViewSize != self.bounds.size else { return }
            s.canvasViewSize = self.bounds.size
        }
        sizeSettle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sizeSettleDelay, execute: work)
    }
    static let sizeSettleDelay = 0.12
    /// Rendered onion-skin frames, reused while those frames don't change.
    private var onionCache: [(layers: [ArtLayer], key: String, image: CGImage)] = []
    private func drawMotionPath(_ ctx: CGContext, studio s: Studio) {
        let pts = s.motionPathPoints()
        guard Studio.pathMoves(pts) else { return }
        let k = 1 / max(geometry.scale, 0.01)
        ctx.saveGState()
        let accent = NSColor.controlAccentColor.cgColor
        ctx.setStrokeColor(accent.copy(alpha: 0.7) ?? accent); ctx.setLineWidth(1.5 * k); ctx.setLineDash(phase: 0, lengths: [4 * k, 3 * k])
        var started = false
        for p in pts { guard let p else { started = false; continue }; if started { ctx.addLine(to: p) } else { ctx.move(to: p); started = true } }
        ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
        for (i, p) in pts.enumerated() {
            guard let p else { continue }
            let r = (i == s.frameIndex ? 5 : 3) * k
            ctx.setFillColor(i == s.frameIndex ? accent : CGColor(gray: 1, alpha: 0.95)); ctx.setStrokeColor(accent); ctx.setLineWidth(1.2 * k)
            ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)); ctx.drawPath(using: .fillStroke)
        }
        ctx.restoreGState()
    }
    private func referenceImage(_ frame: [ArtLayer], studio s: Studio) -> CGImage? {
        let key = "\(s.width)x\(s.height)-reference"
        if let hit = onionCache.first(where: { $0.key == key && $0.layers == frame }) { return hit.image }
        guard let plain = Renderer.render(layers:s.composite(frame),width:s.width,height:s.height) else { return nil }
        let image = OnionSettings.tint(plain,color:Studio.referenceColor) ?? plain
        onionCache.append((frame, key, image)); if onionCache.count > 12 { onionCache.removeFirst() }
        return image
    }
    private func onionImage(_ frame: [ArtLayer], before: Bool, settings o: OnionSettings, studio s: Studio) -> CGImage? {
        let key = "\(s.width)x\(s.height)-\(o.tinted)-\(before)"
        if let hit = onionCache.first(where: { $0.key == key && $0.layers == frame }) { return hit.image }
        guard let plain = Renderer.render(layers:s.composite(frame),width:s.width,height:s.height) else { return nil }
        let image = o.tinted ? (OnionSettings.tint(plain,color:before ? OnionSettings.beforeColor : OnionSettings.afterColor) ?? plain) : plain
        onionCache.append((frame, key, image)); if onionCache.count > 12 { onionCache.removeFirst() }
        return image
    }
    private var sizeSettle: DispatchWorkItem?
    /// The transparency checkerboard of the current document size, drawn once instead of per square.
    private var checker: (size: CGSize, image: CGImage)?
    private func checkerImage(width: Int, height: Int) -> CGImage? {
        let size = CGSize(width: width, height: height)
        if let checker, checker.size == size { return checker.image }
        guard let image = Renderer.checkerboard(width: width, height: height) else { return nil }
        checker = (size, image); return image
    }
    var grid = false; var rulers = true; var snap = false; var motionPath = false;var backdrop:NSColor = .windowBackgroundColor
    private var cachedLayers: [ArtLayer] = []; private var cachedSize = CGSize.zero
    private var image: CGImage?
    private let layerCache = LayerImageCache()
    private var active: InkStroke?
    private var start = CGPoint.zero; private var previous = CGPoint.zero
    private var originalTransform: LayerTransform?
    private var moveStart: [UUID: LayerTransform] = [:]
    private enum TransformDrag { case move, scale, rotate }
    private var transformDrag: TransformDrag?
    private var transformStart = LayerTransform()
    private var transformCentre = CGPoint.zero
    private var remoteActive = false; private var lastRemote = Date.distantPast
    private var interactionBegan = false
    /// Pen tool: the node whose handles the current drag pulls out.
    private var penGrab: PenGrab?
    private var cropGrab: CropGrab?
    private var distortCorner: Int?
    /// Selection outline being dragged: the selection at the press and the press point.
    private var selectionDrag: (CanvasSelection, CGPoint)?
    private var selectionFrameGrab: CropGrab?
    private var rotateStart: (Double, Double)?
    private var lastRemoteScreen: CGPoint?
    private var pointer = CGPoint.zero; private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var geometry: CanvasGeometry { guard let s = studio else { return CanvasGeometry(size: bounds.size, document: CGSize(width:1200,height:800),zoom:1,pan:.zero,rotation:0,mirrored:false) }; return CanvasGeometry(size: bounds.size, document: CGSize(width:s.width,height:s.height), zoom:s.zoom,pan:s.pan,rotation:s.rotation,mirrored:s.mirrored) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let t = NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseMoved,.mouseEnteredAndExited,.inVisibleRect],owner:self); addTrackingArea(t); tracking = t }
    func committedImage() -> CGImage? {
        guard let s = studio else { return nil }
        let shown = s.composite(s.layers)
        if cachedLayers != shown || cachedSize != CGSize(width:s.width,height:s.height) || image == nil {
            image = Renderer.render(layers:shown,width:s.width,height:s.height,cache:layerCache); cachedLayers = shown; cachedSize = CGSize(width:s.width,height:s.height)
        }
        return image
    }
    private func drawImage(_ img: CGImage, in c: CGContext, rect: CGRect) {
        c.saveGState(); c.translateBy(x:rect.minX,y:rect.maxY); c.scaleBy(x:1,y:-1); c.draw(img,in:CGRect(origin:.zero,size:rect.size)); c.restoreGState()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let s = studio, let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Since macOS 14 views may paint outside their bounds: keep the picture inside the canvas area.
        ctx.clip(to:bounds)
        backdrop.setFill(); bounds.fill()
        let doc = CGRect(x:0,y:0,width:s.width,height:s.height)
        ctx.saveGState(); ctx.concatenate(geometry.transform)
        ctx.setShadow(offset:CGSize(width:0,height:3),blur:20,color:CGColor(gray:0,alpha:0.22)); ctx.setFillColor(CGColor(gray:0.9,alpha:1)); ctx.fill(doc); ctx.setShadow(offset:.zero,blur:0)
        ctx.saveGState(); ctx.clip(to:doc)
        // Small reusable checker tile avoids one view per square.
        let cell = 16.0
        if let board = checkerImage(width:s.width,height:s.height) { ctx.interpolationQuality = .none; drawImage(board,in:ctx,rect:doc); ctx.interpolationQuality = .default }
        else { ctx.setFillColor(CGColor(gray:0.97,alpha:1)); ctx.fill(doc) }
        _ = cell
        if let r = s.referenceFrame, r != s.frameIndex, s.frames.indices.contains(r), !s.isPlaying,
           let ref = referenceImage(s.frames[r], studio: s) { ctx.setAlpha(0.3); drawImage(ref,in:ctx,rect:doc); ctx.setAlpha(1) }
        if s.onionSkin && !s.isPlaying {
            let o = OnionSettings(defaults:.standard)
            for g in o.ghosts(current:s.frameIndex,count:s.frames.count,loop:s.loop) where s.frames.indices.contains(g.index) {
                if let ghost = onionImage(o.ghostLayers(s.frames[g.index],activeID:s.activeLayer?.id),before:g.isBefore,settings:o,studio:s) { ctx.setAlpha(g.alpha); drawImage(ghost,in:ctx,rect:doc); ctx.setAlpha(1) }
            }
        }
        let rendered: CGImage?
        if let active = active ?? s.distortStroke, s.layers.indices.contains(s.selectedLayer) { if s.maskEditing || s.activeLayer?.isAdjustmentLayer == true { var previewLayers = s.composite(s.layers);previewLayers[s.selectedLayer].mask = (previewLayers[s.selectedLayer].mask ?? []) + [active];rendered = Renderer.render(layers:previewLayers,width:s.width,height:s.height,cache:layerCache) } else { rendered = Renderer.render(layers:s.composite(s.layers),width:s.width,height:s.height,preview:active,previewLayer:s.selectedLayer,cache:layerCache) } } else { rendered = committedImage() }
        if let rendered { drawImage(rendered,in:ctx,rect:doc) }
        if motionPath && !s.isPlaying { drawMotionPath(ctx, studio: s) }
        if Studio.pixelGridOn, let lines = Studio.pixelGridLines(visible:bounds.applying(geometry.transform.inverted()),width:s.width,height:s.height,scale:geometry.scale) {
            ctx.saveGState(); ctx.setStrokeColor(CGColor(gray:0.5,alpha:0.35)); ctx.setLineWidth(1 / max(geometry.scale,0.01))
            for x in lines.xs { ctx.move(to:CGPoint(x:x,y:lines.ys.first ?? 0)); ctx.addLine(to:CGPoint(x:x,y:lines.ys.last ?? 0)) }
            for y in lines.ys { ctx.move(to:CGPoint(x:lines.xs.first ?? 0,y:y)); ctx.addLine(to:CGPoint(x:lines.xs.last ?? 0,y:y)) }
            ctx.strokePath(); ctx.restoreGState()
        }
        if grid { ctx.setStrokeColor(CGColor(gray:0.4,alpha:0.25)); ctx.setLineWidth(0.5 / max(geometry.scale,0.01)); for x in stride(from:0,through:s.width,by:50) { ctx.move(to:CGPoint(x:x,y:0)); ctx.addLine(to:CGPoint(x:x,y:s.height)) }; for y in stride(from:0,through:s.height,by:50) { ctx.move(to:CGPoint(x:0,y:y)); ctx.addLine(to:CGPoint(x:s.width,y:y)) }; ctx.strokePath() }
        if s.transformMode, let corners = s.transformCorners() {
            let line = 1/max(geometry.scale,0.01), h = 4*line
            ctx.setLineWidth(line); ctx.setStrokeColor(NSColor(PhotoTheme.mint).cgColor)
            ctx.addLines(between:corners); ctx.closePath(); ctx.strokePath()
            ctx.setFillColor(CGColor(gray:1,alpha:1))
            for c in corners { let r = CGRect(x:c.x-h,y:c.y-h,width:2*h,height:2*h); ctx.fill(r); ctx.stroke(r) }
        }
        if let selection = s.selection, let mask = selection.mask {
            // Pixel selection: tint what is selected, dashed box around it.
            ctx.saveGState(); ctx.translateBy(x:0,y:CGFloat(s.height)); ctx.scaleBy(x:1,y:-1)
            ctx.clip(to:CGRect(x:0,y:0,width:mask.width,height:mask.height),mask:mask)
            ctx.setFillColor(NSColor(PhotoTheme.mint).withAlphaComponent(0.28).cgColor); ctx.fill(CGRect(x:0,y:0,width:s.width,height:s.height)); ctx.restoreGState()
            ctx.setLineWidth(1/max(geometry.scale,0.01)); ctx.setStrokeColor(CGColor(gray:0,alpha:0.9)); ctx.setLineDash(phase:0,lengths:[5/max(geometry.scale,0.01),5/max(geometry.scale,0.01)]); ctx.stroke(selection.bounds); ctx.setLineDash(phase:0,lengths:[])
        } else if let selection = s.selection { let path = selectionPath(selection); ctx.setLineWidth(1/max(geometry.scale,0.01)); ctx.setStrokeColor(CGColor(gray:1,alpha:1)); ctx.addPath(path); ctx.strokePath(); ctx.setStrokeColor(CGColor(gray:0,alpha:0.9)); ctx.setLineDash(phase:0,lengths:[5/max(geometry.scale,0.01),5/max(geometry.scale,0.01)]); ctx.addPath(path); ctx.strokePath(); ctx.setLineDash(phase:0,lengths:[]) }
        if s.showGuides && !s.guides.isEmpty {
            ctx.saveGState(); ctx.setLineWidth(1/max(geometry.scale,0.01)); ctx.setStrokeColor(NSColor(red:0.2,green:0.85,blue:1,alpha:0.9).cgColor)
            let far = 100_000.0
            for g in s.guides { if g.vertical { ctx.move(to:CGPoint(x:g.position,y:-far)); ctx.addLine(to:CGPoint(x:g.position,y:far)) } else { ctx.move(to:CGPoint(x:-far,y:g.position)); ctx.addLine(to:CGPoint(x:far,y:g.position)) } }
            ctx.strokePath(); ctx.restoreGState()
        }
        if s.tool == .text, let id = s.editingText, let layer = s.activeLayer, let stroke = layer.strokes.first(where: { $0.id == id }) {
            // Edited text: dashed frame (layer pixels placed like the layer).
            let line = 1/max(geometry.scale,0.01)
            ctx.saveGState(); ctx.concatenate(s.matrix(layer.transform))
            ctx.setLineWidth(line/max(layer.transform.scale,0.01)); ctx.setStrokeColor(NSColor(PhotoTheme.mint).cgColor); ctx.setLineDash(phase:0,lengths:[4*line,3*line])
            ctx.stroke(Renderer.textBounds(stroke).insetBy(dx:-3,dy:-3)); ctx.restoreGState()
        }
        if s.symmetry != .off, [.brush,.eraser].contains(s.tool) {
            // Symmetry axes through the canvas centre.
            let line = 1/max(geometry.scale,0.01), c = s.symmetryPivot, r = 2*hypot(Double(s.width),Double(s.height))
            ctx.saveGState(); ctx.clip(to:doc); ctx.setLineWidth(line); ctx.setStrokeColor(NSColor(PhotoTheme.mint).withAlphaComponent(0.7).cgColor); ctx.setLineDash(phase:0,lengths:[6*line,4*line])
            let angles: [Double]
            switch s.symmetry { case .vertical: angles = [.pi/2]; case .horizontal: angles = [0]; case .quad: angles = [0,.pi/2]; case .radial: angles = (0..<max(2,s.symmetrySegments)).map { Double($0) * .pi / Double(max(2,s.symmetrySegments)) - .pi/2 }; case .off: angles = [] }
            for a in angles { ctx.move(to:CGPoint(x:c.x-cos(a)*r,y:c.y-sin(a)*r)); ctx.addLine(to:CGPoint(x:c.x+cos(a)*r,y:c.y+sin(a)*r)) }
            ctx.strokePath(); ctx.setLineDash(phase:0,lengths:[]); ctx.setFillColor(NSColor(PhotoTheme.mint).cgColor); ctx.fillEllipse(in:CGRect(x:c.x-4*line,y:c.y-4*line,width:8*line,height:8*line)); ctx.restoreGState()
        }
        if let r = s.selectionFrame {
            let line = 1/max(geometry.scale,0.01), h = 4*line
            ctx.saveGState(); ctx.concatenate(s.selectionFrameTransform); ctx.setStrokeColor(NSColor(PhotoTheme.mint).cgColor); ctx.setLineWidth(1.2*line); ctx.stroke(r)
            ctx.setFillColor(CGColor(gray:1,alpha:1))
            for x in [r.minX,r.midX,r.maxX] { for y in [r.minY,r.midY,r.maxY] where !(x == r.midX && y == r.midY) { let q = CGRect(x:x-h,y:y-h,width:2*h,height:2*h); ctx.fill(q); ctx.stroke(q) } }
            ctx.restoreGState()
        }
        if let corners = s.distortCorners {
            let line = 1/max(geometry.scale,0.01), h = 4.5*line
            ctx.saveGState(); ctx.setLineWidth(1.2*line); ctx.setStrokeColor(NSColor(PhotoTheme.mint).cgColor)
            ctx.addLines(between:corners); ctx.closePath(); ctx.strokePath()
            ctx.setFillColor(CGColor(gray:1,alpha:1)); for q in corners { let r = CGRect(x:q.x-h,y:q.y-h,width:2*h,height:2*h); ctx.fill(r); ctx.stroke(r) }
            ctx.restoreGState()
        }
        if let r = s.cropRect, s.tool == .crop {
            // Crop frame: dim what goes, thirds inside, handles on corners and edges.
            let line = 1/max(geometry.scale,0.01), h = 4*line
            ctx.saveGState()
            ctx.addRect(doc.insetBy(dx:-100_000,dy:-100_000)); ctx.addRect(r); ctx.setFillColor(CGColor(gray:0,alpha:0.5)); ctx.fillPath(using:.evenOdd)
            ctx.setStrokeColor(CGColor(gray:1,alpha:0.45)); ctx.setLineWidth(line)
            for k in 1...2 { let fx = r.minX + r.width*Double(k)/3, fy = r.minY + r.height*Double(k)/3; ctx.move(to:CGPoint(x:fx,y:r.minY)); ctx.addLine(to:CGPoint(x:fx,y:r.maxY)); ctx.move(to:CGPoint(x:r.minX,y:fy)); ctx.addLine(to:CGPoint(x:r.maxX,y:fy)) }
            ctx.strokePath()
            ctx.setStrokeColor(CGColor(gray:1,alpha:1)); ctx.setLineWidth(1.5*line); ctx.stroke(r)
            ctx.setFillColor(CGColor(gray:1,alpha:1))
            for x in [r.minX,r.midX,r.maxX] { for y in [r.minY,r.midY,r.maxY] where !(x == r.midX && y == r.midY) { ctx.fill(CGRect(x:x-h,y:y-h,width:2*h,height:2*h)) } }
            ctx.restoreGState()
        }
        if let path = s.penPath, !path.nodes.isEmpty {
            // Pen path: the curve, its anchors as squares and the handles of each node.
            let line = 1/max(geometry.scale,0.01), h = 3.5*line
            ctx.saveGState(); ctx.setLineWidth(1.5*line); ctx.setStrokeColor(NSColor(red:0.2,green:0.55,blue:1,alpha:0.95).cgColor); ctx.addPath(path.cgPath); ctx.strokePath()
            ctx.setLineWidth(line)
            for (i, n) in path.nodes.enumerated() {
                let handles = [n.out, PenPath.inHandle(n)].compactMap { $0 }.filter { $0 != n.anchor }
                if !handles.isEmpty {
                    for q in handles { ctx.move(to:n.anchor); ctx.addLine(to:q) }; ctx.strokePath()
                    for q in handles { ctx.setFillColor(CGColor(gray:1,alpha:1)); ctx.fillEllipse(in:CGRect(x:q.x-h*0.8,y:q.y-h*0.8,width:h*1.6,height:h*1.6)); ctx.strokeEllipse(in:CGRect(x:q.x-h*0.8,y:q.y-h*0.8,width:h*1.6,height:h*1.6)) }
                }
                let r = CGRect(x:n.anchor.x-h,y:n.anchor.y-h,width:2*h,height:2*h)
                ctx.setFillColor(i == 0 && !path.closed ? NSColor(PhotoTheme.mint).cgColor : CGColor(gray:1,alpha:1)); ctx.fill(r); ctx.stroke(r)
            }
            ctx.restoreGState()
        }
        if let hover = s.hoverPoint, [.clone,.heal].contains(s.tool), let source = s.cloneSourceMarker(for:hover) {
            // Where the stamp copies from: a ring with a cross.
            let r = s.brushSize/2, line = 1/max(geometry.scale,0.01)
            ctx.setLineWidth(line); ctx.setStrokeColor(CGColor(gray:1,alpha:0.9)); ctx.strokeEllipse(in:CGRect(x:source.x-r,y:source.y-r,width:r*2,height:r*2))
            ctx.move(to:CGPoint(x:source.x-6*line,y:source.y)); ctx.addLine(to:CGPoint(x:source.x+6*line,y:source.y)); ctx.move(to:CGPoint(x:source.x,y:source.y-6*line)); ctx.addLine(to:CGPoint(x:source.x,y:source.y+6*line)); ctx.strokePath()
        }
        if let hover = s.hoverPoint, [.brush,.eraser,.clone,.heal,.smudge,.liquify,.dodge,.focus].contains(s.tool) { ctx.setStrokeColor(CGColor(gray:0.2,alpha:0.7)); ctx.setLineWidth(1/max(geometry.scale,0.01)); let r = s.brushSize/2; ctx.strokeEllipse(in:CGRect(x:hover.x-r,y:hover.y-r,width:r*2,height:r*2)) }
        ctx.restoreGState(); ctx.setStrokeColor(CGColor(gray:0.35,alpha:0.6)); ctx.setLineWidth(1/max(geometry.scale,0.01)); ctx.stroke(doc); ctx.restoreGState()
        if rulers { drawRulers() }
    }
    private func drawRulers() {
        NSColor.controlBackgroundColor.withAlphaComponent(0.9).setFill(); NSRect(x:0,y:0,width:bounds.width,height:20).fill(); NSRect(x:0,y:0,width:20,height:bounds.height).fill()
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:9,weight:.regular),.foregroundColor:NSColor.secondaryLabelColor]
        let g = geometry
        for value in stride(from:0,through:studio?.width ?? 1200,by:100) { let p = CGPoint(x:value,y:0).applying(g.transform); if p.x > 24 && p.x < bounds.width { ("\(value)" as NSString).draw(at:CGPoint(x:p.x+3,y:3),withAttributes:attributes) } }
        for value in stride(from:100,through:studio?.height ?? 800,by:100) { let p = CGPoint(x:0,y:value).applying(g.transform); if p.y > 24 && p.y < bounds.height { ("\(value)" as NSString).draw(at:CGPoint(x:2,y:p.y),withAttributes:attributes) } }
    }
    func selectionPath(_ s: CanvasSelection) -> CGPath { let p = CGMutablePath(); if s.ellipse { p.addEllipse(in:s.bounds) } else if s.points.count == 2 { p.addRect(s.bounds) } else if let first = s.points.first { p.move(to:first); s.points.dropFirst().forEach { p.addLine(to:$0) }; p.closeSubpath() }; return p }
    private func documentPoint(_ p: CGPoint) -> CGPoint {
        var q = geometry.toDocument(p); if snap { q.x = (q.x/25).rounded()*25; q.y = (q.y/25).rounded()*25 }
        // Guides, canvas edges and centre pull within 6 screen points.
        if let s = studio, ![.brush,.eraser,.clone,.heal,.smudge,.liquify,.dodge,.focus].contains(s.tool) { q = s.snappedToGuides(q, tolerance: 6/max(geometry.scale,0.01)) }
        return q
    }
    /// Guide being dragged (from a ruler, or an existing one with the move tool).
    private var draggingGuide: UUID?
    private func guideDown(_ p: CGPoint) -> Bool {
        guard let s = studio else { return false }
        let d = geometry.toDocument(p)
        if rulers && (p.y < 20 || p.x < 20), !s.guidesLocked {
            let vertical = p.x < 20 && p.y >= 20
            s.addGuide(vertical: vertical, at: vertical ? d.x : d.y); draggingGuide = s.guides.last?.id; return true
        }
        if s.tool == .move, let g = s.guide(near: d, tolerance: 4/max(geometry.scale,0.01)) { s.checkpoint("Move guide"); draggingGuide = g.id; return true }
        return false
    }
    private func guideDrag(_ p: CGPoint) -> Bool {
        guard let id = draggingGuide, let s = studio, let g = s.guides.first(where: { $0.id == id }) else { return draggingGuide != nil }
        let d = geometry.toDocument(p); s.moveGuide(id, to: g.vertical ? d.x : d.y); needsDisplay = true; return true
    }
    private func localPoint(_ p: CGPoint) -> CGPoint { guard let s = studio, let t = s.activeLayer?.transform else { return p }; let transform = CGAffineTransform(translationX:t.x+Double(s.width)/2,y:t.y+Double(s.height)/2).rotated(by:t.rotation * .pi/180).scaledBy(x:t.scaleX,y:t.scaleY).translatedBy(x:-Double(s.width)/2,y:-Double(s.height)/2); return p.applying(transform.inverted()) }
    private func isDuplicate(_ e: NSEvent) -> Bool {
        // UniversePen tags its injected Pencil CGEvents with this device ID (Host/InputInjector).
        // Claim only that route after a validated subscription; ordinary mice and tablets remain usable.
        studio?.pen.connected == true && e.cgEvent?.getIntegerValueField(.tabletEventDeviceID) == 0x7AFE1
    }
    override func mouseDown(with e:NSEvent) { window?.makeFirstResponder(self); guard !isDuplicate(e) else { return }; if guideDown(convert(e.locationInWindow,from:nil)) { return }; begin(at:convert(e.locationInWindow,from:nil),pressure:pressure(e),tilt: e.subtype == .tabletPoint ? e.tilt : .zero,rotation:Double(e.rotation)) }
    override func mouseDragged(with e:NSEvent) { guard !isDuplicate(e) else { return }; if guideDrag(convert(e.locationInWindow,from:nil)) { return }; drag(at:convert(e.locationInWindow,from:nil),pressure:pressure(e),tilt:e.subtype == .tabletPoint ? e.tilt : .zero,rotation:Double(e.rotation)) }
    override func mouseUp(with e:NSEvent) { guard !isDuplicate(e) else { return }; if draggingGuide != nil { _ = guideDrag(convert(e.locationInWindow,from:nil)); draggingGuide = nil; return }; if interactionBegan { drag(at:convert(e.locationInWindow,from:nil),pressure:pressure(e),tilt:e.subtype == .tabletPoint ? e.tilt : .zero,rotation:Double(e.rotation)) };finish() }
    override func mouseMoved(with e:NSEvent) { pointer = convert(e.locationInWindow,from:nil); let d = geometry.toDocument(pointer); studio?.hoverPoint = d; if let s = studio { let inside = CGRect(x:0,y:0,width:s.width,height:s.height).contains(d); let c = inside ? committedImage().map { Renderer.sample($0,at:d) } : nil; if s.hoverColor != c { s.hoverColor = c } }; needsDisplay = true }
    override func mouseExited(with e:NSEvent) { studio?.hoverPoint = nil; needsDisplay = true }
    private func pressure(_ e:NSEvent) -> Double { e.subtype == .tabletPoint ? max(0.05,Double(e.pressure)) : 1 }
    private func begin(at p:CGPoint,pressure:Double,tilt:CGPoint = .zero,rotation:Double = 0) {
        guard let s = studio,!s.isPlaying else { return }; interactionBegan = false; active = nil; originalTransform = nil; start = p; previous = p
        if let frame = s.selectionFrame {
            let d = geometry.toDocument(p), tol = 8/max(geometry.scale,0.01), grab = Studio.frameGrab(frame,at:s.frameSpace(d),tolerance:tol)
            if case .new = grab {
                if s.selectionRotateZone(d,tolerance:tol) {
                    s.beginSelectionRotation()
                    rotateStart = (s.selectionAngle, atan2(d.y-s.selectionPivot.y,d.x-s.selectionPivot.x)); interactionBegan = true; return
                }
                s.applySelectionTransform(); needsDisplay = true; return
            }
            selectionFrameGrab = grab; interactionBegan = true; return
        }
        if let corners = s.distortCorners {
            // Distort: grab the nearest corner within 12 screen points.
            let view = corners.map { $0.applying(geometry.transform) }
            distortCorner = view.indices.min { hypot(view[$0].x-p.x,view[$0].y-p.y) < hypot(view[$1].x-p.x,view[$1].y-p.y) }.flatMap { hypot(view[$0].x-p.x,view[$0].y-p.y) < 12 ? $0 : nil }
            interactionBegan = distortCorner != nil; return
        }
        if s.transformMode, s.canEdit, let corners = s.transformCorners() {
            // Corners scale, inside moves, outside rotates – all around the content's centre.
            let view = corners.map { $0.applying(geometry.transform) }
            transformCentre = CGPoint(x:view.map(\.x).reduce(0,+)/4,y:view.map(\.y).reduce(0,+)/4)
            let path = CGMutablePath(); path.addLines(between:view); path.closeSubpath()
            transformDrag = view.contains { hypot($0.x-p.x,$0.y-p.y) < 11 } ? .scale : path.contains(p) ? .move : .rotate
            transformStart = s.activeLayer?.transform ?? .init(); s.checkpoint("Transform"); interactionBegan = true; return
        }
        let doc = documentPoint(p); guard CGRect(x:0,y:0,width:s.width,height:s.height).contains(doc) || s.tool == .pan || s.tool == .crop else { return }
        interactionBegan = true
        if s.tool == .pan { return }
        if s.settingSymmetryCenter, [.brush,.eraser].contains(s.tool) { s.symmetryCenter = doc; s.settingSymmetryCenter = false; interactionBegan = false; needsDisplay = true; return }
        if s.tool == .text, s.beginTextEdit(at:doc) { interactionBegan = false; needsDisplay = true; return }
        if s.tool == .text { s.editingText = nil }
        if s.tool == .eyedropper { if let c = s.pickColor(at:doc,from:s.eyedropperAllLayers ? committedImage() : nil) { s.color = c }; return }
        if s.tool == .crop { cropGrab = s.cropPress(at:doc,tolerance:8/max(geometry.scale,0.01)); needsDisplay = true; return }
        if s.tool == .pen { penGrab = s.penPress(at:geometry.toDocument(p),place:doc,tolerance:8/max(geometry.scale,0.01),corner:NSEvent.modifierFlags.contains(.option)); needsDisplay = true; return }
        if [.rectangleSelection,.ellipseSelection,.lasso].contains(s.tool), NSEvent.modifierFlags.isDisjoint(with:[.shift,.option,.command]), let sel = s.selection, s.selectionContains(doc) { selectionDrag = (sel,doc); return }
        if [.rectangleSelection,.ellipseSelection,.lasso].contains(s.tool) { s.selection = CanvasSelection(points:[doc,doc],ellipse:s.tool == .ellipseSelection); return }
        if s.tool == .wand {
            let flags = NSEvent.modifierFlags
            s.magicWand(at:doc,combine:flags.contains(.shift) ? .add : flags.contains(.option) ? .subtract : .replace); interactionBegan = false; needsDisplay = true; return
        }
        guard s.canEdit else { return }
        if s.tool == .move {
            // Moving with a selection lifts the selected pixels onto their own layer first (like Photoshop).
            if s.selection != nil { s.layerFromSelection(cut:true) }
            s.checkpoint("Move"); originalTransform = s.activeLayer?.transform; moveStart = s.beginMove(); return
        }
        var c = s.color; c.alpha *= s.brushOpacity
        let paintsMask = s.maskEditing || s.activeLayer?.isAdjustmentLayer == true
        if paintsMask { c = s.eraser ? .white : CodableColor(red:0,green:0,blue:0,alpha:1) }
        if s.quickMaskActive, s.activeLayer?.id == s.quickMaskLayer { c = Studio.quickMaskRed; c.alpha = s.brushOpacity }
        let local = localPoint(doc)
        var stroke = InkStroke(points:[InkPoint(x:local.x,y:local.y,pressure:s.mapPressure(pressure),tiltX:tilt.x,tiltY:tilt.y,rotation:rotation)],color:c,width:s.brushSize,isEraser:s.eraser && !paintsMask)
        if s.tool == .brush && !s.eraser && !paintsMask && s.brushTip != .round { stroke.brushTip = s.brushTip.rawValue }
        if s.pressureOpacity, s.tool == .eraser || (s.tool == .brush && s.brushTip == .round) { stroke.pressureOpacity = true }
        if s.tool == .brush && !s.eraser && !paintsMask && s.brushTip == .round {
            if s.brushScatter > 0 { stroke.scatter = s.brushScatter }
            if s.brushSizeJitter > 0 { stroke.sizeJitter = s.brushSizeJitter }
            if s.brushHueJitter > 0 { stroke.hueJitter = s.brushHueJitter }
        }
        if s.tool == .brush && !s.eraser && !paintsMask && s.brushBlend != .normal { stroke.blend = s.brushBlend }
        if [.brush,.eraser].contains(s.tool), let code = s.symmetry.code(segments:s.symmetrySegments) {
            let c = localPoint(s.symmetryPivot); stroke.symmetry = code; stroke.symmetryX = c.x; stroke.symmetryY = c.y
        }
        if let selection = s.selection, let maskData = selection.maskData {
            stroke.selectionMask = maskData
        } else if let selection = s.selection {
            // Persist the selection in layer coordinates. Sampling an ellipse before the inverse
            // transform preserves its true boundary on translated, rotated and scaled layers.
            let points: [CGPoint]
            if selection.ellipse {
                let b = selection.bounds
                points = (0..<96).map { i in let a = Double(i) * 2 * .pi / 96; return CGPoint(x:b.midX + cos(a)*b.width/2,y:b.midY + sin(a)*b.height/2) }
            } else if selection.points.count == 2 {
                let b = selection.bounds
                points = [CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY)]
            } else { points = selection.points }
            stroke.selectionPoints = points.map { let p = localPoint($0); return InkPoint(x:p.x,y:p.y,pressure:1) }
            stroke.selectionEllipse = false
        }
        switch s.tool {
        case .clone, .heal:
            if NSEvent.modifierFlags.contains(.option) { s.setCloneSource(doc); interactionBegan = false; needsDisplay = true; return }
            stroke.kind = s.tool == .clone ? "clone" : "heal"
            guard s.beginClone(id:stroke.id,at:doc) else { interactionBegan = false; return }
        case .smudge: stroke.kind = "smudge"; stroke.strength = s.toolStrength; s.beginSmudge(id:stroke.id,at:local)
        case .liquify: stroke.kind = "liquify"; stroke.strength = s.toolStrength; s.beginLiquify(id:stroke.id,at:local)
        case .dodge: stroke.kind = s.toneMode.rawValue; stroke.strength = s.toolStrength
        case .focus: stroke.kind = s.sharpenMode ? "sharpenBrush" : "blurBrush"; stroke.strength = s.toolStrength
        default: break
        }
        switch s.tool { case .rectangle:stroke.kind = s.shapeStyle.kind;stroke.filled = s.shapeFill ? true : nil;if let r = s.shapeStyle.parameter { stroke.strength = min(r.upperBound,max(r.lowerBound,s.shapeParameter)) }; case .ellipse:stroke.kind = "ellipse";stroke.filled = s.shapeFill ? true : nil; case .line:stroke.kind = s.lineArrow ? "arrow" : "line"; case .text:stroke.kind = "text";stroke.text = s.textContent;stroke.fontName = NSFontManager.shared.font(withFamily:s.fontFamily,traits:NSFontTraitMask(rawValue:(s.textBold ? NSFontTraitMask.boldFontMask.rawValue : 0) | (s.textItalic ? NSFontTraitMask.italicFontMask.rawValue : 0)),weight:5,size:12)?.fontName;stroke.width = max(10,s.brushSize);stroke.textAlign = s.textAlign == .left ? nil : s.textAlign.rawValue;stroke.tracking = s.textTracking == 0 ? nil : s.textTracking;stroke.lineSpacing = abs(s.textLineSpacing-1.2) < 0.01 ? nil : s.textLineSpacing; case .fill:stroke.kind = "fill"; case .gradient:stroke.kind = s.gradientStyle.kind;stroke.gradientStops = s.gradientStops;stroke.secondaryColor = s.secondaryColor; default:break }
        if s.tool == .bucket {
            guard var fill = s.bucketStroke(at:local,documentPoint:doc) else { interactionBegan = false; return }
            fill.selectionPoints = stroke.selectionPoints; fill.selectionEllipse = stroke.selectionEllipse; fill.selectionMask = stroke.selectionMask
            active = fill; finish(); return
        }
        active = stroke; if s.tool == .text || s.tool == .fill { finish() }; needsDisplay = true
    }
    private func drag(at p:CGPoint,pressure:Double,tilt:CGPoint = .zero,rotation:Double = 0) {
        guard let s = studio, interactionBegan else { return }
        if let g = selectionFrameGrab { s.updateSelectionFrame(Studio.frameDrag(g,to:s.frameSpace(geometry.toDocument(p)),square:NSEvent.modifierFlags.contains(.shift))); needsDisplay = true; return }
        if let (a0,p0) = rotateStart { let d = geometry.toDocument(p); s.rotateSelectionFrame(to:a0 + (atan2(d.y-s.selectionPivot.y,d.x-s.selectionPivot.x)-p0)*180 / .pi,snap:NSEvent.modifierFlags.contains(.shift)); needsDisplay = true; return }
        if let i = distortCorner { s.moveDistortCorner(i,to:geometry.toDocument(p)); needsDisplay = true; return }
        if s.tool == .pan { s.pan.width += p.x-previous.x;s.pan.height += p.y-previous.y;previous = p;return }
        if s.tool == .crop { if let g = cropGrab { s.cropDrag(g,to:documentPoint(p),square:NSEvent.modifierFlags.contains(.shift)) }; needsDisplay = true; return }
        if s.tool == .pen { if let g = penGrab { s.penMove(g,to:documentPoint(p)) }; needsDisplay = true; return }
        if let mode = transformDrag {
            var t = transformStart
            switch mode {
            case .move: let a = geometry.toDocument(start), b = geometry.toDocument(p); t.x += b.x-a.x; t.y += b.y-a.y
            case .scale:
                let factor = hypot(p.x-transformCentre.x,p.y-transformCentre.y) / max(1,hypot(start.x-transformCentre.x,start.y-transformCentre.y))
                t = s.transformKeepingCentre(from:transformStart,scale:transformStart.scale*factor,rotation:transformStart.rotation)
            case .rotate:
                var deg = (atan2(p.y-transformCentre.y,p.x-transformCentre.x) - atan2(start.y-transformCentre.y,start.x-transformCentre.x)) * 180 / .pi
                if s.mirrored { deg = -deg }
                var angle = transformStart.rotation + deg
                if NSEvent.modifierFlags.contains(.shift) { angle = (angle/15).rounded()*15 }
                angle = (angle+540).truncatingRemainder(dividingBy:360)-180
                t = s.transformKeepingCentre(from:transformStart,scale:transformStart.scale,rotation:angle)
            }
            s.layers[s.selectedLayer].transform = t; needsDisplay = true; return
        }
        let doc = documentPoint(p)
        if let (original,from) = selectionDrag { let d = geometry.toDocument(p); if let moved = s.movedSelection(original,by:CGPoint(x:d.x-from.x,y:d.y-from.y)) { s.selection = moved }; needsDisplay = true; return }
        if var selection = s.selection, [.rectangleSelection,.ellipseSelection,.lasso].contains(s.tool) { if s.tool == .lasso { selection.points.append(doc) } else { selection.points = [documentPoint(start),doc] };s.selection = selection;return }
        if s.tool == .move, originalTransform != nil { let a = geometry.toDocument(start); s.move(moveStart,by:CGSize(width:doc.x-a.x,height:doc.y-a.y)); needsDisplay = true;return }
        guard var stroke = active else { return }; let q = localPoint(doc)
        var point = InkPoint(x:q.x,y:q.y,pressure:s.mapPressure(pressure),tiltX:tilt.x,tiltY:tilt.y,rotation:rotation)
        if stroke.isFreehand, let last = stroke.points.last { let factor = 1-s.smoothing*0.85;point.x = last.x+(point.x-last.x)*factor;point.y = last.y+(point.y-last.y)*factor; if hypot(point.x-last.x,point.y-last.y) < 0.15 { return } }
        if !stroke.isFreehand { stroke.points = [stroke.points[0],point] } else { stroke.points.append(point) }
        if stroke.kind == "smudge" { s.smudge(id:stroke.id,to:q) }
        if stroke.kind == "liquify" { s.liquify(id:stroke.id,to:q) }
        active = stroke; needsDisplay = true
    }
    private func finish() { guard let s = studio else { return }; penGrab = nil; cropGrab = nil; distortCorner = nil; selectionDrag = nil; selectionFrameGrab = nil; rotateStart = nil; if s.cropRect.map({ $0.width < 2 || $0.height < 2 }) == true { s.cropRect = nil }; if transformDrag != nil { transformDrag = nil; s.changed() }; if let stroke = active { s.add(stroke) }; if originalTransform != nil { s.changed() }; active = nil; originalTransform = nil; interactionBegan = false; needsDisplay = true }
    private func cancelInteraction() {
        if let s = studio, originalTransform != nil { s.move(moveStart,by:.zero) }
        if let s = studio, transformDrag != nil, s.layers.indices.contains(s.selectedLayer) { s.layers[s.selectedLayer].transform = transformStart }; transformDrag = nil
        active = nil; originalTransform = nil; interactionBegan = false; needsDisplay = true
    }
    func remote(_ sample:PenSample) {
        guard let s = studio else { return }
        // Disconnect/disable emits a coordinate-free cancel. It must release the remote route
        // even after focus has moved, otherwise native input remains suppressed indefinitely.
        if sample.phase == "cancel" || sample.phase == "exit" {
            if remoteActive { cancelInteraction() }
            remoteActive = false; lastRemote = .distantPast; lastRemoteScreen = nil; s.hoverPoint = nil; needsDisplay = true; return
        }
        guard window?.isKeyWindow == true, NSApp.isActive else {
            if remoteActive { cancelInteraction(); remoteActive = false }
            return
        }
        guard let sx = sample.screenX,let sy = sample.screenY else { return } // normalized picture coordinates alone don't identify the canvas on screen
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let global = CGPoint(x:sx,y:mainHeight-sy)
        let p = convert(window!.convertPoint(fromScreen:global),from:nil)
        lastRemote = Date(); lastRemoteScreen = global
        if sample.phase == "hover" || sample.phase == "enter" { s.hoverPoint = geometry.toDocument(p); needsDisplay = true;return }
        if sample.phase == "down" { active = nil; remoteActive = true; begin(at:p,pressure:sample.pressure,tilt:CGPoint(x:sample.tiltX ?? 0,y:sample.tiltY ?? 0),rotation:sample.rotation ?? 0) }
        if sample.phase == "move" && remoteActive { drag(at:p,pressure:sample.pressure,tilt:CGPoint(x:sample.tiltX ?? 0,y:sample.tiltY ?? 0),rotation:sample.rotation ?? 0) }
        if sample.phase == "up" && remoteActive { drag(at:p,pressure:sample.pressure,tilt:CGPoint(x:sample.tiltX ?? 0,y:sample.tiltY ?? 0),rotation:sample.rotation ?? 0);finish();remoteActive = false }
    }
    /// Two-finger scrolling moves the picture with the fingers (scrollingDelta already follows the system's scroll direction).
    override func scrollWheel(with e:NSEvent) { guard let s = studio else { return }; if e.modifierFlags.contains(.command) { s.zoom = max(0.1,min(16,s.zoom * exp(e.scrollingDeltaY*0.01))) } else { s.pan.width += e.scrollingDeltaX;s.pan.height += e.scrollingDeltaY } }
    override func magnify(with e:NSEvent) { guard let s = studio else { return };s.zoom = max(0.1,min(16,s.zoom*(1+e.magnification))) }
    override func rotate(with e:NSEvent) { studio?.rotation += Double(e.rotation) }
    override func keyDown(with e:NSEvent) { guard let s = studio else { return }; if [.rectangleSelection,.ellipseSelection,.lasso,.wand].contains(s.tool), s.selection != nil, let arrow = [123:(-1.0,0.0),124:(1.0,0.0),125:(0.0,1.0),126:(0.0,-1.0)][Int(e.keyCode)] { let step = e.modifierFlags.contains(.shift) ? 10.0 : 1.0; s.nudgeSelection(dx:arrow.0*step,dy:arrow.1*step); needsDisplay = true; return }; if s.transformingSelection, e.keyCode == 53 { s.cancelSelectionTransform(); needsDisplay = true; return }; if s.transformingSelection, e.keyCode == 36 || e.keyCode == 76 { s.applySelectionTransform(); needsDisplay = true; return }; if s.distorting, e.keyCode == 53 { s.cancelDistort(); needsDisplay = true; return }; if s.distorting, e.keyCode == 36 || e.keyCode == 76 { s.applyDistort(); needsDisplay = true; return }; if e.keyCode == 53, s.editingText != nil { s.editingText = nil; needsDisplay = true; return }; if e.keyCode == 53, s.cropRect != nil { s.cropRect = nil; needsDisplay = true; return }; if e.keyCode == 36 || e.keyCode == 76, s.tool == .crop, s.cropRect != nil { s.applyCrop(); needsDisplay = true; return }; if e.keyCode == 53, s.tool == .pen, s.penPath != nil { s.penPath = nil; s.editingPath = nil; needsDisplay = true; return }; if e.keyCode == 51, s.tool == .pen, s.penPath != nil { s.penDeleteLast(); needsDisplay = true; return }; if e.keyCode == 53 { s.selection = nil;s.transformMode = false;cancelInteraction();remoteActive = false;return }; if e.keyCode == 36 && s.transformMode { s.transformMode = false; return };super.keyDown(with:e) }
}
