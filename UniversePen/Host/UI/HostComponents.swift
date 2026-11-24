import SwiftUI
import TafelKit

// Building blocks of the Mac window, the menu bar panel and the setup (UltraUI).

/// State light of the connection: rings while waiting, a glowing orb with the link once connected.
/// `animated: false` for the menu bar panel, which lives on hidden in the background.
struct ConnectionOrb: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let connected: Bool
    let usb: Bool
    var animated = true

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                if animated { PulseRings(color: Brand.mint, active: !connected) }
                Circle()
                    .fill(connected ? AnyShapeStyle(Ultra.accentFill) : AnyShapeStyle(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(connected ? AnyShapeStyle(Color.white.opacity(0.4)) : AnyShapeStyle(Ultra.edgeLight), lineWidth: 1))
                    .shadow(color: connected ? Brand.mint.opacity(0.65) : .clear, radius: s * 0.2)
                Image(systemName: connected ? (usb ? "cable.connector" : "wifi") : "ipad.landscape")
                    .font(.system(size: s * 0.36, weight: .semibold))
                    .foregroundStyle(connected ? Brand.slateDeep : .white.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(Ultra.bouncy, value: connected)
        .accessibilityHidden(true)
    }
}

/// Small capsule with a symbol: link type, battery, warnings.
struct UltraChip: View {
    let text: String
    let symbol: String
    var color: Color = .white

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
            .foregroundStyle(color == .white ? Color.white.opacity(0.85) : color)
    }
}

struct LinkChip: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let link: String
    var body: some View {
        let usb = link.hasPrefix("USB")
        UltraChip(text: link.isEmpty ? L("verbunden") : localizedLink(link),
                  symbol: usb ? "cable.connector" : "wifi", color: usb ? Brand.mintBright : .orange)
    }
}

struct BatteryChip: View {
    let level: Double
    let charging: Bool
    var body: some View {
        let pct = Int((level * 100).rounded())
        let symbol = charging ? "battery.100percent.bolt"
            : pct > 87 ? "battery.100percent" : pct > 62 ? "battery.75percent"
            : pct > 37 ? "battery.50percent" : pct > 12 ? "battery.25percent" : "battery.0percent"
        UltraChip(text: "\(pct) %", symbol: symbol, color: pct <= 15 && !charging ? .orange : .white)
            .accessibilityLabel(L("iPad-Akku: %d %%", pct))
    }
}

/// fps, bit rate and dropped frames. Observes only the live numbers (they change every second).
struct StatTiles: View {
    @ObservedObject var live: LiveStats
    var body: some View {
        let s = live.stats
        HStack(spacing: 10) {
            StatTile(value: String(format: "%.0f", s.fps), unit: L("Bilder/s"), symbol: "film", history: live.fpsHistory)
            StatTile(value: String(format: "%.1f", s.mbps),
                     unit: s.targetMbps > 0 ? L("Mbit/s · Ziel %.0f", s.targetMbps) : "Mbit/s",
                     symbol: "arrow.up.right", history: live.mbpsHistory)
            StatTile(value: "\(s.dropped)", unit: L("verworfen"), symbol: "tray.and.arrow.down")
        }
    }
}

private struct StatTile: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let value: String
    let unit: String
    let symbol: String
    var history: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(Brand.mint)
            // No rolling digits: they change every second and are drawn on the CPU.
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
            Text(unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            // The last minute as a soft line along the bottom (drawn once per update, no animation).
            if history.count > 2 { Sparkline(values: history).frame(height: 30).padding(.bottom, 6).allowsHitTesting(false) }
        }
        .background(.black.opacity(0.18), in: Ultra.shape(14))
        .overlay(Ultra.shape(14).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        .clipShape(Ultra.shape(14))
    }
}

/// A minute of values as a line with a soft fill below, scaled to its own maximum.
private struct Sparkline: View {
    @ObservedObject var theme = Theme.shared
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            let top = max(values.max() ?? 1, 0.001) * 1.15
            let step = size.width / CGFloat(max(values.count - 1, 1))
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(v / top) * size.height)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: CGFloat(values.count - 1) * step, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [Brand.mint.opacity(0.22), Brand.mint.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(Brand.mint.opacity(0.55)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Link symbol and "fps · Mbit/s" in one line (menu bar panel).
struct StatsLine: View {
    @ObservedObject var live: LiveStats
    let link: String
    var body: some View {
        let s = live.stats
        Label {
            Text(s.fps > 0 ? String(format: "%.0f fps · %.1f Mbit/s", s.fps, s.mbps) : localizedLink(link))
                .lineLimit(1)
        } icon: {
            Image(systemName: link.hasPrefix("USB") ? "cable.connector" : "wifi")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .help(localizedLink(link))
    }
}

/// One setting: symbol tile, title, explanation, control on the right.
struct SettingRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    var detailColor: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.09), in: Ultra.shape(9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 6)
    }
}

extension SettingRow where Trailing == EmptyView {
    init(symbol: String, title: String, detail: String? = nil, detailColor: Color = .secondary) {
        self.init(symbol: symbol, title: title, detail: detail, detailColor: detailColor) { EmptyView() }
    }
}

/// Switch with the accent colour (as a trailing control of a `SettingRow`).
struct UltraSwitch: View {
    @ObservedObject var theme = Theme.shared
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(label, isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Brand.mint)
    }
}

/// A card of rows with hairlines between them.
struct UltraSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { UltraHeader(title).padding(.leading, 6) }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.leading, 42) }
                        row
                    }
                }
            }
            .ultraCard(padding: 14)
        }
    }
}

/// Countdown of the pairing code.
struct CountdownRing: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let fraction: Double
    let seconds: Int
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Ultra.accentFill, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
            Text("\(seconds)")
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
                .animation(Ultra.snappy, value: seconds)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%d Sekunden", seconds))
    }
}

/// The pairing code as the iPad asks for it: three groups of four boxes.
struct PairingCodeView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let code: String
    let seconds: Int
    var cancel: (() -> Void)?
    @State private var shown = false

    var body: some View {
        VStack(spacing: 18) {
            UltraBadge("key.horizontal", size: 54)
                .scaleEffect(shown ? 1 : 0.6)
            VStack(spacing: 5) {
                Text(L("Auf dem iPad eingeben")).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(L("Öffne UniversePen auf dem iPad, tippe unter „Neu koppeln“ auf diesen Mac und gib den Code ein."))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                ForEach(Array(groups.enumerated()), id: \.offset) { gi, group in
                    HStack(spacing: 5) {
                        ForEach(Array(group.enumerated()), id: \.offset) { ci, ch in
                            Text(String(ch))
                                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 42)
                                .background(.black.opacity(0.25), in: Ultra.shape(9))
                                .overlay(Ultra.shape(9).strokeBorder(Brand.mint.opacity(0.35), lineWidth: 1))
                                .opacity(shown ? 1 : 0)
                                .offset(y: shown ? 0 : 10)
                                .animation(Ultra.bouncy.delay(Double(gi * 4 + ci) * 0.025), value: shown)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(code.map(String.init).joined(separator: " "))
            .textSelection(.enabled)
            HStack(spacing: 12) {
                CountdownRing(fraction: Double(seconds) / 120, seconds: seconds)
                    .frame(width: 34, height: 34)
                if let cancel {
                    Button(L("Abbrechen"), action: cancel)
                        .buttonStyle(UltraQuiet(compact: true))
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .onAppear { withAnimation(Ultra.bouncy) { shown = true } }
    }

    private var groups: [[Character]] {
        stride(from: 0, to: code.count, by: 4).map { i in
            Array(code.dropFirst(i).prefix(4))
        }
    }
}
