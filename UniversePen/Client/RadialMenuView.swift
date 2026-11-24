import SwiftUI
import TafelKit

/// Actions on an arc around the Pencil tip (like the squeeze palettes of drawing apps), opened by
/// squeeze (or double tap) when set to "Radialmenü". Hover over a button and squeeze again, or tap
/// it. Tap the tip or outside to close. The arc opens upwards and turns away from screen edges.
/// The highlight change and the pick give a haptic tick on the Pencil Pro.
struct RadialMenuView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    let center: CGPoint
    @State private var shown = false

    private var items: [ShortcutButton] { model.effectiveSettings.radialMenu }

    var body: some View {
        GeometryReader { g in
            let origin = g.frame(in: .global).origin
            let c = CGPoint(x: center.x - origin.x, y: center.y - origin.y)
            let n = items.count
            let facing = RadialMenuLayout.facing(x: c.x, y: c.y, width: g.size.width, height: g.size.height, count: n)
            let r = RadialMenuLayout.radius(count: n)
            ZStack {
                // Catches taps outside (close) and keeps the Pencil off the Mac meanwhile.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeRadial() }

                // Glass band under the buttons: an open arc, not a full ring.
                if n > 1 {
                    ArcBand(center: c, radius: r,
                            from: RadialMenuLayout.angle(of: 0, count: n, facing: facing),
                            to: RadialMenuLayout.angle(of: n - 1, count: n, facing: facing),
                            width: RadialMenuLayout.buttonSize + 14)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            ArcBand(center: c, radius: r,
                                    from: RadialMenuLayout.angle(of: 0, count: n, facing: facing),
                                    to: RadialMenuLayout.angle(of: n - 1, count: n, facing: facing),
                                    width: RadialMenuLayout.buttonSize + 14)
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                        .scaleEffect(shown ? 1 : 0.4, anchor: UnitPoint(x: c.x / max(g.size.width, 1), y: c.y / max(g.size.height, 1)))
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(false)
                }

                // Small dot at the Pencil tip; tap closes.
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 8, height: 8)
                    .shadow(color: Brand.mint.opacity(0.8), radius: 6)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .position(c)
                    .onTapGesture { model.closeRadial() }

                // Name of the highlighted action, on the far side of the arc.
                if let h = model.radialHighlight, items.indices.contains(h) {
                    let a = RadialMenuLayout.angle(of: h, count: n, facing: facing)
                    let lr = r + RadialMenuLayout.buttonSize / 2 + 26
                    Text(items[h].title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .tafelOverlayGlass(Capsule())
                        .fixedSize()
                        .position(x: c.x + lr * cos(a), y: c.y + lr * sin(a))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .id(h)
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let o = RadialMenuLayout.offset(of: i, count: n, facing: facing)
                    let a = RadialMenuLayout.angle(of: i, count: n, facing: facing)
                    let on = model.radialHighlight == i
                    // The highlighted button pops a little outwards.
                    let push: Double = on ? 7 : 0
                    RadialButton(item: item, on: on)
                        .position(x: shown ? c.x + o.x + push * cos(a) : c.x,
                                  y: shown ? c.y + o.y + push * sin(a) : c.y)
                        .scaleEffect(shown ? 1 : 0.3)
                        .opacity(shown ? 1 : 0)
                        .animation(Brand.spring.delay(Double(i) * 0.022), value: shown)
                        .onTapGesture { model.pickRadial(i) }
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    let i = RadialMenuLayout.item(dx: p.x - c.x, dy: p.y - c.y, count: n, facing: facing)
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
}

/// One round button on the arc: glass when idle, filled with the accent colour when highlighted.
private struct RadialButton: View {
    let item: ShortcutButton
    let on: Bool

    var body: some View {
        Group {
            if let tool = item.tool {
                VStack(spacing: 1) {
                    Image(systemName: tool.symbol).font(.system(size: 17, weight: .semibold))
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
            .padding(6)
            .foregroundStyle(on ? Brand.slateDeep : .primary)
            .frame(width: RadialMenuLayout.buttonSize, height: RadialMenuLayout.buttonSize)
            .background {
                Circle().fill(on ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(0.12)))
            }
            .overlay(Circle().strokeBorder(.white.opacity(on ? 0.5 : 0.16), lineWidth: 1))
            .shadow(color: on ? Brand.mint.opacity(0.55) : .black.opacity(0.2), radius: on ? 12 : 4, y: on ? 0 : 2)
            .scaleEffect(on ? 1.14 : 1)
            .contentShape(Circle())
    }
}

/// A thick open arc with round ends (the band the buttons sit on).
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
