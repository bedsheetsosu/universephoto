import SwiftUI
import TafelKit

/// The Pencil palette (1.1, replaces the arc of the radial menu): a small grid of actions that
/// opens next to the Pencil tip on squeeze (or double tap) and stays open while you use it.
/// Tap a button – or hover over it and squeeze – to run it; the palette stays. Close it with the
/// ✕, by squeezing while not over a button, or by tapping outside. Drag the handle to move it.
struct PencilPaletteView: View {
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    let center: CGPoint
    @State private var shown = false
    @State private var moved: CGSize = .zero
    @GestureState private var dragging: CGSize = .zero

    private var items: [ShortcutButton] { model.effectiveSettings.radialMenu }

    var body: some View {
        GeometryReader { g in
            let origin = g.frame(in: .global).origin
            let n = items.count
            let size = PaletteGridLayout.size(count: n)
            let o = PaletteGridLayout.origin(tipX: center.x - origin.x, tipY: center.y - origin.y, width: g.size.width, height: g.size.height, count: n)
            // Where the panel is now (moved by its handle), kept on screen.
            let px = min(max(PaletteGridLayout.margin, o.x + moved.width + dragging.width), g.size.width - size.width - PaletteGridLayout.margin)
            let py = min(max(PaletteGridLayout.margin, o.y + moved.height + dragging.height), g.size.height - size.height - PaletteGridLayout.margin)
            ZStack(alignment: .topLeading) {
                // Catches taps outside (close) and keeps the Pencil off the Mac meanwhile.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeRadial() }

                panel(n: n)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .tafelOverlayGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .scaleEffect(shown ? 1 : 0.6, anchor: UnitPoint(x: 0.5, y: center.y - origin.y > py ? 1 : 0))
                    .opacity(shown ? 1 : 0)
                    .offset(x: px, y: py)
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    let i = PaletteGridLayout.item(x: p.x - px, y: p.y - py, count: n)
                    if i != model.radialHighlight { model.radialHighlight = i }
                case .ended:
                    model.radialHighlight = nil
                }
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: model.radialHighlight)
        .sensoryFeedback(.alignment, trigger: model.radialHighlight) { _, new in new != nil }
        .onAppear { withAnimation(Brand.spring) { shown = true } }
        .transition(.opacity)
    }

    private func panel(n: Int) -> some View {
        VStack(spacing: 0) {
            // Header: grab handle to move the palette, ✕ to close it.
            HStack {
                Capsule().fill(.white.opacity(0.35)).frame(width: 34, height: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .updating($dragging) { v, s, _ in s = v.translation }
                        .onEnded { v in moved.width += v.translation.width; moved.height += v.translation.height })
                    .accessibilityLabel(L("Palette verschieben"))
                Button { model.closeRadial() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain).padding(.trailing, 8)
                .accessibilityLabel(L("Schließen"))
            }
            .frame(height: PaletteGridLayout.header)
            .padding(.leading, 34)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(PaletteGridLayout.button), spacing: PaletteGridLayout.gap), count: PaletteGridLayout.columns(count: n)),
                      spacing: PaletteGridLayout.gap) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    PaletteButton(item: item, highlighted: model.radialHighlight == i, active: item.tool.map(model.isOn) ?? false)
                        .scaleEffect(shown ? 1 : 0.5)
                        .animation(Brand.spring.delay(Double(i) * 0.018), value: shown)
                        .onTapGesture { model.runPalette(i) }
                }
            }
            .padding(.horizontal, PaletteGridLayout.padding)
            Spacer(minLength: 0)
        }
    }
}

/// One square button of the palette: glass when idle, accent when hovered, a ring when the tool
/// it switches is on.
private struct PaletteButton: View {
    let item: ShortcutButton
    let highlighted: Bool
    let active: Bool

    var body: some View {
        Group {
            if let tool = item.tool {
                VStack(spacing: 2) {
                    Image(systemName: tool.symbol).font(.system(size: 18, weight: .semibold))
                    Text(item.title).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                }
            } else {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(5)
        .foregroundStyle(highlighted ? Brand.slateDeep : .primary)
        .frame(width: PaletteGridLayout.button, height: PaletteGridLayout.button)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlighted ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(active ? 0.22 : 0.1)))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(active ? Brand.mint : .white.opacity(highlighted ? 0.5 : 0.14), lineWidth: active ? 2 : 1))
        .shadow(color: highlighted ? Brand.mint.opacity(0.5) : .clear, radius: 10)
        .scaleEffect(highlighted ? 1.06 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
