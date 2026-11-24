import SwiftUI

/// Navigator: a small picture of the whole document with the visible part outlined.
/// Clicking or dragging in it centres the view there; the slider zooms.
extension Studio {
    func geometry(viewSize: CGSize, pan p: CGSize? = nil) -> CanvasGeometry {
        CanvasGeometry(size: viewSize, document: CGSize(width: width, height: height), zoom: zoom, pan: p ?? pan, rotation: rotation, mirrored: mirrored)
    }

    /// The visible part of the document as four corners (a turned view gives a turned frame).
    func visibleQuad(viewSize v: CGSize) -> [CGPoint] {
        let g = geometry(viewSize: v)
        return [CGPoint.zero, CGPoint(x: v.width, y: 0), CGPoint(x: v.width, y: v.height), CGPoint(x: 0, y: v.height)].map(g.toDocument)
    }

    /// Pans so that `p` (document pixels) sits in the middle of the view.
    func centerView(on p: CGPoint, viewSize v: CGSize) {
        let at = p.applying(geometry(viewSize: v, pan: .zero).transform)
        pan = CGSize(width: v.width / 2 - at.x, height: v.height / 2 - at.y)
    }
}

struct NavigatorPanel: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @State private var thumb: CGImage?
    private let side = 176.0

    var body: some View {
        let docSize = CGSize(width: s.width, height: s.height)
        let k = min(side / docSize.width, side / docSize.height)
        let box = CGSize(width: docSize.width * k, height: docSize.height * k)
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let thumb { ZStack { Checkerboard(); Image(decorative: thumb, scale: 1).resizable().interpolation(.medium) } }
                    else { Rectangle().fill(theme.card) }
                }.frame(width: box.width, height: box.height)
                Path { p in
                    let q = s.visibleQuad(viewSize: s.canvasViewSize).map { CGPoint(x: $0.x * k, y: $0.y * k) }
                    p.addLines(q); p.closeSubpath()
                }
                .stroke(theme.accent, lineWidth: 1.5)
                .background(Path { p in
                    let q = s.visibleQuad(viewSize: s.canvasViewSize).map { CGPoint(x: $0.x * k, y: $0.y * k) }
                    p.addLines(q); p.closeSubpath()
                }.fill(theme.accent.opacity(0.10)))
            }
            .frame(width: box.width, height: box.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.outline, lineWidth: 0.7))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                s.centerView(on: CGPoint(x: g.location.x / k, y: g.location.y / k), viewSize: s.canvasViewSize)
            })
            .accessibilityLabel(L("Navigator"))
            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass").font(.system(size: 10)).foregroundStyle(theme.secondary)
                Slider(value: Binding(get: { log2(s.zoom) }, set: { s.zoom = pow(2, $0) }), in: log2(0.1)...log2(16)).controlSize(.mini)
                Image(systemName: "plus.magnifyingglass").font(.system(size: 10)).foregroundStyle(theme.secondary)
                Text("\(Int((s.zoom * 100).rounded()))%").font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundStyle(theme.secondary).frame(width: 38, alignment: .trailing)
            }.frame(width: max(box.width, 150))
        }
        .padding(10)
        .photoChrome(radius: 14)
        .task(id: s.undoStack.count * 7919 + s.tabs.count * 31 + s.width + s.height + s.selectedLayer) {
            let layers = s.composite(s.layers), w = s.width, h = s.height
            try? await Task.sleep(for: .milliseconds(120))   // a burst of edits renders once
            guard !Task.isCancelled else { return }
            let target = Double(side * 2) / Double(max(w, h))
            let small = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let full = Renderer.render(layers: layers, width: w, height: h) else { return nil }
                return ImageFiles.scaled(full, by: min(1, target))
            }.value
            if !Task.isCancelled, let small { thumb = small }
        }
    }
}
