import SwiftUI
import TafelKit

/// The Pencil palette (1.1): a dark arc next to the Pencil tip, opened by squeeze (or double tap)
/// when set to "Stift-Palette" – icons right on the band, thin lines between kinds of actions, the
/// iPad tool that is on in a coloured circle. It stays open while you use it: tap an icon, or
/// hover over it and squeeze. With more than seven actions, drag along the arc to scroll; its ends
/// fade where more wait. Squeeze over nothing, tap the tip or tap outside to close.
struct PencilPaletteView: View {
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    let center: CGPoint
    @State private var shown = false
    /// `-debugPaletteScroll N` starts scrolled by N actions (UI checks).
    @State private var scroll = Double(UserDefaults.standard.integer(forKey: "debugPaletteScroll"))
    @State private var dragAngle: Double?
    /// The accent circle slides from the old choice to the new one.
    @Namespace private var selection

    private var items: [ShortcutButton] { model.paletteItems }

    var body: some View {
        GeometryReader { g in
            let origin = g.frame(in: .global).origin
            let c = CGPoint(x: center.x - origin.x, y: center.y - origin.y)
            let n = items.count, v = RadialMenuLayout.visible(count: n)
            let facing = RadialMenuLayout.facing(x: c.x, y: c.y, width: g.size.width, height: g.size.height, count: n)
            let r = RadialMenuLayout.radius(count: v)
            let half = Double(v - 1) / 2 * RadialMenuLayout.step(count: v) + RadialMenuLayout.step(count: v) * 0.5
            let from = facing - half, to = facing + half
            let more = (start: scroll > 0.05, end: scroll < RadialMenuLayout.maxScroll(count: n) - 0.05)
            ZStack {
                // Catches taps outside (close) and keeps the Pencil off the Mac meanwhile.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeRadial() }

                // The band, with a drag along it to scroll.
                ArcBand(center: c, radius: r, from: from, to: to, width: RadialMenuLayout.bandWidth)
                    .fill(Color(white: 0.11))
                    .overlay { ArcBand(center: c, radius: r, from: from, to: to, width: RadialMenuLayout.bandWidth).stroke(.white.opacity(0.08), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .allowsHitTesting(false)
                    .scaleEffect(shown ? 1 : 0.5, anchor: UnitPoint(x: c.x / max(g.size.width, 1), y: c.y / max(g.size.height, 1)))
                    .opacity(shown ? 1 : 0)

                // Thin lines where the kind of action changes.
                ForEach(ShortcutButton.paletteSeparators(items), id: \.self) { k in
                    let a = (RadialMenuLayout.angle(of: k, count: n, facing: facing, scroll: scroll) + RadialMenuLayout.angle(of: k + 1, count: n, facing: facing, scroll: scroll)) / 2
                    let op = min(RadialMenuLayout.opacity(of: k, count: n, scroll: scroll), RadialMenuLayout.opacity(of: k + 1, count: n, scroll: scroll))
                    Path { p in
                        let i = r - RadialMenuLayout.bandWidth / 2 + 12, o = r + RadialMenuLayout.bandWidth / 2 - 12
                        p.move(to: CGPoint(x: c.x + i * cos(a), y: c.y + i * sin(a)))
                        p.addLine(to: CGPoint(x: c.x + o * cos(a), y: c.y + o * sin(a)))
                    }
                    .stroke(.white.opacity(0.2 * op), lineWidth: 1)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(false)
                }

                // Small dot at the Pencil tip; tap closes.
                Circle().fill(.white.opacity(0.9)).frame(width: 7, height: 7)
                    .shadow(color: Brand.mint.opacity(0.8), radius: 6)
                    .frame(width: 44, height: 44).contentShape(Circle())
                    .position(c)
                    .onTapGesture { model.closeRadial() }

                // Name of the hovered action, just outside the arc.
                if let h = model.radialHighlight, items.indices.contains(h) {
                    let a = RadialMenuLayout.angle(of: h, count: n, facing: facing, scroll: scroll)
                    let lr = r + RadialMenuLayout.bandWidth / 2 + 24
                    Text(items[h].title)
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .tafelOverlayGlass(Capsule())
                        .fixedSize()
                        .position(x: c.x + lr * cos(a), y: c.y + lr * sin(a))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .id(h)
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let a = RadialMenuLayout.angle(of: i, count: n, facing: facing, scroll: scroll)
                    let op = RadialMenuLayout.opacity(of: i, count: n, scroll: scroll)
                    if op > 0.01 {
                        let chosen = item.isToolSwitch && model.paletteSelection == item.id
                        PaletteIcon(item: item, highlighted: model.radialHighlight == i, active: item.tool.map(model.isOn) ?? chosen,
                                    selection: chosen ? selection : nil)
                            .position(x: shown ? c.x + r * cos(a) : c.x, y: shown ? c.y + r * sin(a) : c.y)
                            .opacity((shown ? 1 : 0) * op)
                            .scaleEffect(shown ? 1 : 0.4)
                            .animation(Brand.spring.delay(Double(i) * 0.015), value: shown)
                            .onTapGesture { if op > 0.6 { model.runPalette(i) } }
                            .allowsHitTesting(op > 0.6)
                    }
                }
            }
            // Circling anywhere around the tip scrolls (on the arc or beside it); a plain tap
            // beside it still closes.
            .simultaneousGesture(scrollGesture(center: c, count: n))
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    let i = RadialMenuLayout.item(dx: p.x - c.x, dy: p.y - c.y, count: n, facing: facing, scroll: scroll)
                    if i != model.radialHighlight { model.radialHighlight = i }
                case .ended:
                    model.radialHighlight = nil
                }
            }
            // Fade the ends of the band where more actions wait.
            .mask {
                EndFade(center: c, from: from, to: to, fadeStart: more.start, fadeEnd: more.end)
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: model.radialHighlight)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.paletteSelection)
        .sensoryFeedback(.alignment, trigger: model.radialHighlight) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: Int(scroll.rounded()))
        .onAppear { scroll = min(max(0, scroll), RadialMenuLayout.maxScroll(count: items.count)) }
        .onAppear { withAnimation(Brand.spring) { shown = true } }
        .transition(.opacity)
    }

    /// Dragging along the band scrolls through the actions; it settles on whole items.
    private func scrollGesture(center c: CGPoint, count n: Int) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { v in
                // Right at the tip the direction jumps around: ignore that bit.
                guard hypot(v.location.x - c.x, v.location.y - c.y) > 30 else { dragAngle = nil; return }
                let a = atan2(v.location.y - c.y, v.location.x - c.x)
                if let last = dragAngle {
                    scroll = min(max(0, scroll + RadialMenuLayout.scrollDelta(from: last, to: a, count: n)), RadialMenuLayout.maxScroll(count: n))
                }
                dragAngle = a
            }
            .onEnded { _ in
                dragAngle = nil
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { scroll = scroll.rounded() }
            }
    }
}

/// One icon on the band: plain when idle, a soft circle when hovered, a coloured circle when the
/// iPad tool it switches is on.
private struct PaletteIcon: View {
    let item: ShortcutButton
    let highlighted: Bool
    let active: Bool
    /// Set for the current tool choice: its circle is shared, so it slides between icons.
    var selection: Namespace.ID? = nil

    var body: some View {
        ZStack {
            // Hover: a ring in the accent colour (and a soft fill), so you see where a squeeze lands.
            Circle()
                .fill(Brand.mint.opacity(highlighted && !active ? 0.18 : 0))
                .overlay(Circle().strokeBorder(Brand.mint.opacity(highlighted && !active ? 0.9 : 0), lineWidth: 1.5))
                .frame(width: 44, height: 44)
            if active {
                let dot = Circle().fill(Brand.mint).frame(width: 44, height: 44)
                    .shadow(color: Brand.mint.opacity(0.55), radius: 8)
                if let selection { dot.matchedGeometryEffect(id: "choice", in: selection) } else { dot }
            }
            Group {
                if let s = item.tool?.symbol ?? item.paletteSymbol {
                    Image(systemName: s).font(.system(size: 19, weight: .medium))
                } else {
                    Text(item.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                        .minimumScaleFactor(0.55).multilineTextAlignment(.center).frame(width: 40)
                }
            }
            .foregroundStyle(active ? Brand.slateDeep : .white.opacity(0.92))
        }
        .scaleEffect(highlighted ? 1.1 : 1)
        .frame(width: RadialMenuLayout.buttonSize, height: RadialMenuLayout.buttonSize)
        .contentShape(Circle())
        .accessibilityLabel(item.title)
    }
}

/// A thick open arc with round ends (the band the icons sit on).
private struct ArcBand: Shape {
    let center: CGPoint
    let radius: Double
    let from: Double
    let to: Double
    let width: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: center, radius: radius, startAngle: .radians(from), endAngle: .radians(to), clockwise: false)
        return p.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// Mask that fades the arc's ends (angular gradient around the tip) where it can scroll on.
private struct EndFade: View {
    let center: CGPoint
    let from: Double
    let to: Double
    let fadeStart: Bool
    let fadeEnd: Bool

    var body: some View {
        GeometryReader { g in
            // The gradient starts a little before the arc (its round cap) and runs a full turn.
            let g0 = from - 0.3
            let pos = { (a: Double) in min(1, max(0, (a - g0) / (2 * .pi))) }
            let stops: [Gradient.Stop] = [
                .init(color: fadeStart ? .clear : .black, location: 0),
                .init(color: .black, location: fadeStart ? pos(from + 0.35) : 0.0001),
                .init(color: .black, location: fadeEnd ? pos(to - 0.35) : pos(to + 0.3)),
                .init(color: fadeEnd ? .clear : .black, location: pos(to + 0.3)),
                .init(color: .black, location: min(1, pos(to + 0.3) + 0.001)),
                .init(color: .black, location: 1),
            ]
            AngularGradient(stops: stops, center: UnitPoint(x: center.x / max(g.size.width, 1), y: center.y / max(g.size.height, 1)), angle: .radians(g0))
        }
    }
}
