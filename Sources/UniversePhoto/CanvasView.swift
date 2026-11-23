import AppKit
import SwiftUI

struct ArtworkCanvas: NSViewRepresentable {
    @ObservedObject var studio: Studio
    var grid: Bool; var rulers: Bool; var snap: Bool; var background:NSColor = .windowBackgroundColor
    func makeNSView(context: Context) -> ArtworkView { let v = ArtworkView(); v.clipsToBounds = true; v.studio = studio; return v }
    func updateNSView(_ view: ArtworkView, context: Context) { view.studio = studio;view.backdrop = background; view.grid = grid; view.rulers = rulers; view.snap = snap; view.needsDisplay = true; studio.pen.onPen = { [weak view] sample in view?.remote(sample) }; studio.liquifyChanged = { [weak view] in view?.needsDisplay = true } }
}

@MainActor final class ArtworkView: NSView {
    weak var studio: Studio?
    var grid = false; var rulers = true; var snap = false;var backdrop:NSColor = .windowBackgroundColor
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
        ctx.setFillColor(CGColor(gray:0.97,alpha:1)); ctx.fill(doc)
        ctx.setFillColor(CGColor(gray:0.88,alpha:1))
        for y in stride(from:0,to:s.height,by:Int(cell)) { for x in stride(from:0,to:s.width,by:Int(cell)) where (x/Int(cell)+y/Int(cell)) % 2 == 0 { ctx.fill(CGRect(x:x,y:y,width:Int(cell),height:Int(cell))) } }
        if s.onionSkin && s.frameIndex > 0 && s.frames.indices.contains(s.frameIndex-1), let onion = Renderer.render(layers:s.composite(s.frames[s.frameIndex-1]),width:s.width,height:s.height) { ctx.setAlpha(0.2); drawImage(onion,in:ctx,rect:doc); ctx.setAlpha(1) }
        let rendered: CGImage?
        if let active, s.layers.indices.contains(s.selectedLayer) { if s.maskEditing || s.activeLayer?.isAdjustmentLayer == true { var previewLayers = s.composite(s.layers);previewLayers[s.selectedLayer].mask = (previewLayers[s.selectedLayer].mask ?? []) + [active];rendered = Renderer.render(layers:previewLayers,width:s.width,height:s.height,cache:layerCache) } else { rendered = Renderer.render(layers:s.composite(s.layers),width:s.width,height:s.height,preview:active,previewLayer:s.selectedLayer,cache:layerCache) } } else { rendered = committedImage() }
        if let rendered { drawImage(rendered,in:ctx,rect:doc) }
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
                if let out = n.out {
                    let inH = PenPath.inHandle(n)
                    ctx.move(to:inH); ctx.addLine(to:out); ctx.strokePath()
                    for q in [inH, out] { ctx.setFillColor(CGColor(gray:1,alpha:1)); ctx.fillEllipse(in:CGRect(x:q.x-h*0.8,y:q.y-h*0.8,width:h*1.6,height:h*1.6)); ctx.strokeEllipse(in:CGRect(x:q.x-h*0.8,y:q.y-h*0.8,width:h*1.6,height:h*1.6)) }
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
    private func localPoint(_ p: CGPoint) -> CGPoint { guard let s = studio, let t = s.activeLayer?.transform else { return p }; let transform = CGAffineTransform(translationX:t.x+Double(s.width)/2,y:t.y+Double(s.height)/2).rotated(by:t.rotation * .pi/180).scaledBy(x:t.scale,y:t.scale).translatedBy(x:-Double(s.width)/2,y:-Double(s.height)/2); return p.applying(transform.inverted()) }
    private func isDuplicate(_ e: NSEvent) -> Bool {
        // UniversePen tags its injected Pencil CGEvents with this device ID (Host/InputInjector).
        // Claim only that route after a validated subscription; ordinary mice and tablets remain usable.
        studio?.pen.connected == true && e.cgEvent?.getIntegerValueField(.tabletEventDeviceID) == 0x7AFE1
    }
    override func mouseDown(with e:NSEvent) { window?.makeFirstResponder(self); guard !isDuplicate(e) else { return }; if guideDown(convert(e.locationInWindow,from:nil)) { return }; begin(at:convert(e.locationInWindow,from:nil),pressure:pressure(e),tilt: e.subtype == .tabletPoint ? e.tilt : .zero,rotation:Double(e.rotation)) }
    override func mouseDragged(with e:NSEvent) { guard !isDuplicate(e) else { return }; if guideDrag(convert(e.locationInWindow,from:nil)) { return }; drag(at:convert(e.locationInWindow,from:nil),pressure:pressure(e),tilt:e.subtype == .tabletPoint ? e.tilt : .zero,rotation:Double(e.rotation)) }
    override func mouseUp(with e:NSEvent) { guard !isDuplicate(e) else { return }; if draggingGuide != nil { _ = guideDrag(convert(e.locationInWindow,from:nil)); draggingGuide = nil; return }; if interactionBegan { drag(at:convert(e.locationInWindow,from:nil),pressure:pressure(e),tilt:e.subtype == .tabletPoint ? e.tilt : .zero,rotation:Double(e.rotation)) };finish() }
    override func mouseMoved(with e:NSEvent) { pointer = convert(e.locationInWindow,from:nil); studio?.hoverPoint = geometry.toDocument(pointer); needsDisplay = true }
    override func mouseExited(with e:NSEvent) { studio?.hoverPoint = nil; needsDisplay = true }
    private func pressure(_ e:NSEvent) -> Double { e.subtype == .tabletPoint ? max(0.05,Double(e.pressure)) : 1 }
    private func begin(at p:CGPoint,pressure:Double,tilt:CGPoint = .zero,rotation:Double = 0) {
        guard let s = studio,!s.isPlaying else { return }; interactionBegan = false; active = nil; originalTransform = nil; start = p; previous = p
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
        if s.tool == .eyedropper { if let image = committedImage() { s.color = Renderer.sample(image,at:doc) }; return }
        if s.tool == .crop { cropGrab = s.cropPress(at:doc,tolerance:8/max(geometry.scale,0.01)); needsDisplay = true; return }
        if s.tool == .pen { penGrab = s.penPress(at:geometry.toDocument(p),place:doc,tolerance:8/max(geometry.scale,0.01),corner:NSEvent.modifierFlags.contains(.option)); needsDisplay = true; return }
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
        let local = localPoint(doc)
        var stroke = InkStroke(points:[InkPoint(x:local.x,y:local.y,pressure:s.mapPressure(pressure),tiltX:tilt.x,tiltY:tilt.y,rotation:rotation)],color:c,width:s.brushSize,isEraser:s.eraser && !paintsMask)
        if s.tool == .brush && !s.eraser && !paintsMask && s.brushTip != .round { stroke.brushTip = s.brushTip.rawValue }
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
        case .dodge: stroke.kind = s.burnMode ? "burn" : "dodge"; stroke.strength = s.toolStrength
        case .focus: stroke.kind = s.sharpenMode ? "sharpenBrush" : "blurBrush"; stroke.strength = s.toolStrength
        default: break
        }
        switch s.tool { case .rectangle:stroke.kind = s.shapeStyle.kind;stroke.filled = s.shapeFill ? true : nil;if let r = s.shapeStyle.parameter { stroke.strength = min(r.upperBound,max(r.lowerBound,s.shapeParameter)) }; case .ellipse:stroke.kind = "ellipse";stroke.filled = s.shapeFill ? true : nil; case .line:stroke.kind = s.lineArrow ? "arrow" : "line"; case .text:stroke.kind = "text";stroke.text = s.textContent;stroke.fontName = NSFontManager.shared.font(withFamily:s.fontFamily,traits:NSFontTraitMask(rawValue:(s.textBold ? NSFontTraitMask.boldFontMask.rawValue : 0) | (s.textItalic ? NSFontTraitMask.italicFontMask.rawValue : 0)),weight:5,size:12)?.fontName;stroke.width = max(10,s.brushSize);stroke.textAlign = s.textAlign == .left ? nil : s.textAlign.rawValue;stroke.tracking = s.textTracking == 0 ? nil : s.textTracking;stroke.lineSpacing = abs(s.textLineSpacing-1.2) < 0.01 ? nil : s.textLineSpacing; case .fill:stroke.kind = "fill"; case .gradient:stroke.kind = s.gradientStyle.kind;stroke.secondaryColor = s.secondaryColor; default:break }
        if s.tool == .bucket {
            guard var fill = s.bucketStroke(at:local,documentPoint:doc) else { interactionBegan = false; return }
            fill.selectionPoints = stroke.selectionPoints; fill.selectionEllipse = stroke.selectionEllipse; fill.selectionMask = stroke.selectionMask
            active = fill; finish(); return
        }
        active = stroke; if s.tool == .text || s.tool == .fill { finish() }; needsDisplay = true
    }
    private func drag(at p:CGPoint,pressure:Double,tilt:CGPoint = .zero,rotation:Double = 0) {
        guard let s = studio, interactionBegan else { return }
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
    private func finish() { guard let s = studio else { return }; penGrab = nil; cropGrab = nil; if s.cropRect.map({ $0.width < 2 || $0.height < 2 }) == true { s.cropRect = nil }; if transformDrag != nil { transformDrag = nil; s.changed() }; if let stroke = active { s.add(stroke) }; if originalTransform != nil { s.changed() }; active = nil; originalTransform = nil; interactionBegan = false; needsDisplay = true }
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
    override func keyDown(with e:NSEvent) { guard let s = studio else { return }; if e.keyCode == 53, s.cropRect != nil { s.cropRect = nil; needsDisplay = true; return }; if e.keyCode == 36 || e.keyCode == 76, s.tool == .crop, s.cropRect != nil { s.applyCrop(); needsDisplay = true; return }; if e.keyCode == 53, s.tool == .pen, s.penPath != nil { s.penPath = nil; needsDisplay = true; return }; if e.keyCode == 51, s.tool == .pen, s.penPath != nil { s.penDeleteLast(); needsDisplay = true; return }; if e.keyCode == 53 { s.selection = nil;s.transformMode = false;cancelInteraction();remoteActive = false;return }; if e.keyCode == 36 && s.transformMode { s.transformMode = false; return };super.keyDown(with:e) }
}
