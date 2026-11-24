import SwiftUI

/// View → Histogram: a floating panel over the canvas with the picture's tonal spread (all
/// visible layers), per channel or all colours at once, plus mean, deviation, median and pixel count.
struct HistogramStats: Equatable {
    var mean = 0.0, deviation = 0.0, median = 0, pixels = 0

    init(_ counts: [Double]) {
        let total = counts.reduce(0, +); guard total > 0 else { return }
        pixels = Int(total)
        mean = counts.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element } / total
        deviation = sqrt(counts.enumerated().reduce(0) { $0 + pow(Double($1.offset) - mean, 2) * $1.element } / total)
        var acc = 0.0
        for (i, c) in counts.enumerated() { acc += c; if acc >= total / 2 { median = i; break } }
    }
}

enum HistogramChannel: String, CaseIterable, Identifiable {
    case colors, luminosity, red, green, blue
    var id: String { rawValue }
    var title: String { switch self { case .colors: L("Colors"); case .luminosity: L("Luminosity"); case .red: L("Red"); case .green: L("Green"); case .blue: L("Blue") } }
    /// Indices into `AutoTone.histograms`.
    var indices: [Int] { switch self { case .colors: [0, 1, 2]; case .luminosity: [3]; case .red: [0]; case .green: [1]; case .blue: [2] } }
    /// For the numbers: the one channel shown, luminosity for the colour overlay.
    var statsIndex: Int { indices.count == 1 ? indices[0] : 3 }
}

struct HistogramPanel: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @AppStorage("histogramChannel") private var channelRaw = HistogramChannel.colors.rawValue
    @State private var counts: [[Double]] = []
    private let size = CGSize(width: 176, height: 70)

    private var channel: HistogramChannel { HistogramChannel(rawValue: channelRaw) ?? .colors }

    nonisolated static func path(_ counts: [Double], in size: CGSize, peak: Double) -> Path {
        Path { p in
            guard peak > 0, counts.count > 1 else { return }
            p.move(to: CGPoint(x: 0, y: size.height))
            for (i, c) in counts.enumerated() {
                p.addLine(to: CGPoint(x: Double(i) / Double(counts.count - 1) * size.width, y: size.height * (1 - min(1, c / peak))))
            }
            p.addLine(to: CGPoint(x: size.width, y: size.height)); p.closeSubpath()
        }
    }

    var body: some View {
        let shown = counts.isEmpty ? [] : channel.indices.map { counts[$0] }
        // Scale by a high percentile, so one spike (a flat background) doesn't flatten everything.
        let peak = shown.flatMap { $0 }.sorted().dropLast(3).last ?? 0
        let tints = tintColors
        VStack(alignment: .leading, spacing: 7) {
            Picker("", selection: $channelRaw) { ForEach(HistogramChannel.allCases) { Text($0.title).tag($0.rawValue) } }
                .labelsHidden().controlSize(.mini).frame(width: size.width)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(theme.card)
                ForEach(Array(shown.enumerated()), id: \.offset) { i, c in
                    Self.path(c, in: size, peak: peak).fill(tints[i].opacity(channel == .colors ? 0.45 : 0.7)).blendMode(channel == .colors ? .plusLighter : .normal)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.outline, lineWidth: 0.7))
            .accessibilityLabel(L("Histogram"))
            if !counts.isEmpty {
                let st: HistogramStats = HistogramStats(counts[channel.statsIndex])
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                    GridRow { stat(L("Mean"), String(format: "%.1f", st.mean)); stat(L("Median"), "\(st.median)") }
                    GridRow { stat(L("Deviation"), String(format: "%.1f", st.deviation)); stat(L("Pixels"), "\(st.pixels)") }
                }
            }
        }
        .padding(10)
        .photoChrome(radius: 14)
        .task(id: s.undoStack.count * 7919 + s.tabs.count * 31 + s.width + s.height + s.selectedLayer) {
            let layers = s.composite(s.layers), w = s.width, h = s.height
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) { () -> [[Double]] in
                guard let img = Renderer.render(layers: layers, width: w, height: h) else { return [] }
                return AutoTone.histograms(img)
            }.value
            if !Task.isCancelled { counts = result }
        }
    }

    private var tintColors: [Color] {
        switch channel { case .colors: [.red, .green, .blue]; case .red: [.red]; case .green: [.green]; case .blue: [.blue]; case .luminosity: [theme.text] }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(theme.secondary)
            Text(value).monospacedDigit().foregroundStyle(theme.text)
        }.font(.system(size: 9, weight: .medium)).frame(width: 84, alignment: .leading)
    }
}
