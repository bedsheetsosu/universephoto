import SwiftUI

/// Gradient tool: a bar with colour stops. Drag a stop to move it, click the bar to add one in
/// the foreground colour, pick a stop and give it the foreground colour or remove it. Presets
/// for quick starts; "Foreground → background" goes back to the classic two colours.
extension Studio {
    /// The stops the gradient tool paints with right now.
    var effectiveGradientStops: [GradientStop] {
        gradientStops ?? [GradientStop(color: color, location: 0), GradientStop(color: secondaryColor, location: 1)]
    }

    static let gradientPresets: [(String, [GradientStop])] = [
        ("Rainbow", [(1, 0, 0), (1, 0.6, 0), (1, 1, 0), (0, 0.8, 0.2), (0, 0.5, 1), (0.5, 0, 1)].enumerated().map { i, c in
            GradientStop(color: CodableColor(red: c.0, green: c.1, blue: c.2, alpha: 1), location: Double(i) / 5) }),
        ("Sunset", [GradientStop(color: CodableColor(red: 0.16, green: 0.1, blue: 0.4, alpha: 1), location: 0),
                    GradientStop(color: CodableColor(red: 0.9, green: 0.3, blue: 0.45, alpha: 1), location: 0.55),
                    GradientStop(color: CodableColor(red: 1, green: 0.8, blue: 0.4, alpha: 1), location: 1)]),
        ("Chrome", [GradientStop(color: CodableColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1), location: 0),
                    GradientStop(color: CodableColor(red: 0.4, green: 0.42, blue: 0.46, alpha: 1), location: 0.48),
                    GradientStop(color: CodableColor(red: 0.85, green: 0.86, blue: 0.9, alpha: 1), location: 0.52),
                    GradientStop(color: CodableColor(red: 0.3, green: 0.3, blue: 0.33, alpha: 1), location: 1)]),
    ]

    /// Adds a stop at `location` in the foreground colour; returns its index.
    @discardableResult func addGradientStop(at location: Double) -> Int {
        var stops = effectiveGradientStops
        stops.append(GradientStop(color: color, location: max(0, min(1, location))))
        stops.sort { $0.location < $1.location }
        gradientStops = stops
        return stops.firstIndex { $0.location == max(0, min(1, location)) && $0.color == color } ?? 0
    }
    func moveGradientStop(_ i: Int, to location: Double) {
        var stops = effectiveGradientStops; guard stops.indices.contains(i) else { return }
        stops[i].location = max(0, min(1, location)); gradientStops = stops
    }
    func removeGradientStop(_ i: Int) {
        var stops = effectiveGradientStops; guard stops.indices.contains(i), stops.count > 2 else { return }
        stops.remove(at: i); gradientStops = stops
    }
    func setGradientStopColor(_ i: Int, _ c: CodableColor) {
        var stops = effectiveGradientStops; guard stops.indices.contains(i) else { return }
        stops[i].color = c; gradientStops = stops
    }
}

struct GradientEditor: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @State private var picked = 0
    private let barWidth = 260.0

    var body: some View {
        let stops = s.effectiveGradientStops
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Gradient")).font(.system(size: 13, weight: .semibold))
            ZStack(alignment: .topLeading) {
                Checkerboard().frame(width: barWidth, height: 26).clipShape(RoundedRectangle(cornerRadius: 6))
                LinearGradient(stops: stops.sorted { $0.location < $1.location }.map { .init(color: $0.color.color, location: $0.location) }, startPoint: .leading, endPoint: .trailing)
                    .frame(width: barWidth, height: 26).clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.outline))
                    .contentShape(Rectangle())
                    .onTapGesture { p in picked = s.addGradientStop(at: p.x / barWidth) }
                    .help(L("Click to add a stop in the foreground colour"))
                ForEach(stops.indices, id: \.self) { i in
                    handle(stops[i], selected: i == picked)
                        .offset(x: stops[i].location * barWidth - 7, y: 30)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("bar"))
                            .onChanged { g in picked = i; s.moveGradientStop(i, to: g.location.x / barWidth) })
                        .accessibilityLabel(LF("Stop %d", i + 1))
                }
            }
            .coordinateSpace(name: "bar")
            .frame(width: barWidth, height: 50, alignment: .topLeading)
            HStack(spacing: 6) {
                Button(L("Foreground colour")) { s.setGradientStopColor(picked, s.color) }.help(L("Give the selected stop the foreground colour"))
                Button(L("Remove")) { s.removeGradientStop(picked); picked = max(0, picked - 1) }.disabled(stops.count <= 2)
                Spacer()
                Text("\(Int((stops[safe: picked]?.location ?? 0) * 100)) %").monospacedDigit().font(.system(size: 10)).foregroundStyle(theme.secondary)
            }.buttonStyle(PhotoButtonStyle()).controlSize(.small)
            Divider()
            Text(L("Presets")).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondary)
            HStack(spacing: 8) {
                preset(L("Foreground → background"), [GradientStop(color: s.color, location: 0), GradientStop(color: s.secondaryColor, location: 1)]) { s.gradientStops = nil }
                preset(L("Foreground → transparent"), [GradientStop(color: s.color, location: 0), GradientStop(color: { var c = s.color; c.alpha = 0; return c }(), location: 1)]) {
                    var c = s.color; c.alpha = 0
                    s.gradientStops = [GradientStop(color: s.color, location: 0), GradientStop(color: c, location: 1)]
                }
                ForEach(Studio.gradientPresets, id: \.0) { name, stops in preset(L(name), stops) { s.gradientStops = stops } }
            }
        }
        .padding(16).frame(width: barWidth + 32)
    }

    private func handle(_ stop: GradientStop, selected: Bool) -> some View {
        VStack(spacing: 0) {
            Triangle().fill(selected ? theme.accent : theme.secondary).frame(width: 10, height: 6)
            RoundedRectangle(cornerRadius: 3).fill(stop.color.color).frame(width: 14, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? theme.accent : .white.opacity(0.8), lineWidth: selected ? 2 : 1))
        }.contentShape(Rectangle())
    }
    private func preset(_ name: String, _ stops: [GradientStop], apply: @escaping () -> Void) -> some View {
        Button(action: apply) {
            LinearGradient(stops: stops.map { .init(color: $0.color.color, location: $0.location) }, startPoint: .leading, endPoint: .trailing)
                .frame(width: 34, height: 18).clipShape(RoundedRectangle(cornerRadius: 4))
                .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: 4)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.outline))
        }.buttonStyle(PhotoPress()).help(name).accessibilityLabel(name)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath() } }
}

/// The current gradient as a small button in the options bar; opens the editor.
struct GradientButton: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: {
            LinearGradient(stops: s.effectiveGradientStops.sorted { $0.location < $1.location }.map { .init(color: $0.color.color, location: $0.location) }, startPoint: .leading, endPoint: .trailing)
                .frame(width: 46, height: 16).clipShape(RoundedRectangle(cornerRadius: 4))
                .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: 4)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.outline))
        }
        .buttonStyle(PhotoPress()).help(L("Edit gradient")).accessibilityLabel(L("Edit gradient"))
        .popover(isPresented: $open, arrowEdge: .bottom) { GradientEditor().environmentObject(s).environment(\.photoTheme, theme) }
    }
}
