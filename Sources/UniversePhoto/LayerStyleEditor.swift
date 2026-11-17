import SwiftUI

/// Drop shadow, outer glow, outline and colour overlay of the active layer.
struct LayerStyleEditor: View {
    @Environment(\.photoTheme) private var theme
    var style: LayerStyle
    var set: (LayerStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Layer style").uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(theme.secondary)
            effect(L("Drop shadow"), "shadow", on: style.shadow.on, color: style.shadow.color, { var s = style; s.shadow.on = $0; set(s) }, { var s = style; s.shadow.color = $0; set(s) }) {
                slider(L("Opacity"), style.shadow.opacity, 0...1, "%", 100) { var s = style; s.shadow.opacity = $0; set(s) }
                slider(L("Angle"), style.shadow.angle, -180...180, "°", 1) { var s = style; s.shadow.angle = $0; set(s) }
                slider(L("Distance"), style.shadow.distance, 0...100, " px", 1) { var s = style; s.shadow.distance = $0; set(s) }
                slider(L("Softness"), style.shadow.blur, 0...80, " px", 1) { var s = style; s.shadow.blur = $0; set(s) }
            }
            effect(L("Outer glow"), "sun.max", on: style.glow.on, color: style.glow.color, { var s = style; s.glow.on = $0; set(s) }, { var s = style; s.glow.color = $0; set(s) }) {
                slider(L("Opacity"), style.glow.opacity, 0...1, "%", 100) { var s = style; s.glow.opacity = $0; set(s) }
                slider(L("Size"), style.glow.size, 1...100, " px", 1) { var s = style; s.glow.size = $0; set(s) }
            }
            effect(L("Outline"), "circle.circle", on: style.outline.on, color: style.outline.color, { var s = style; s.outline.on = $0; set(s) }, { var s = style; s.outline.color = $0; set(s) }) {
                slider(L("Width"), style.outline.width, 1...40, " px", 1) { var s = style; s.outline.width = $0; set(s) }
                slider(L("Opacity"), style.outline.opacity, 0...1, "%", 100) { var s = style; s.outline.opacity = $0; set(s) }
            }
            effect(L("Color overlay"), "paintbrush", on: style.overlay.on, color: style.overlay.color, { var s = style; s.overlay.on = $0; set(s) }, { var s = style; s.overlay.color = $0; set(s) }) {
                slider(L("Opacity"), style.overlay.opacity, 0...1, "%", 100) { var s = style; s.overlay.opacity = $0; set(s) }
            }
        }
    }

    @ViewBuilder private func effect<Content: View>(_ title: String, _ symbol: String, on: Bool, color: CodableColor,
                                                   _ toggle: @escaping (Bool) -> Void, _ recolor: @escaping (CodableColor) -> Void,
                                                   @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(on ? theme.accent : theme.secondary).frame(width: 16)
                Toggle(title, isOn: Binding(get: { on }, set: { v in withAnimation(PhotoMotion.panel) { toggle(v) } })).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                Spacer()
                if on { ColorPicker(title, selection: Binding(get: { color.color }, set: { recolor(CodableColor($0)) }), supportsOpacity: false).labelsHidden().frame(width: 26) }
            }
            if on { VStack(spacing: 8) { content() }.padding(.leading, 24).transition(.opacity.combined(with: .move(edge: .top))) }
        }
    }

    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double>, _ suffix: String, _ mult: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 4) {
            HStack { Text(title).font(.system(size: 10)); Spacer(); Text("\(Int(value * mult))\(suffix)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary) }
            Slider(value: Binding(get: { value }, set: set), in: range).controlSize(.mini).accessibilityLabel(title)
        }
    }
}
