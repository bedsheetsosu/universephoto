import AppKit
import SwiftUI

/// Colour helpers: hex, HSB, harmonies.
extension CodableColor {
    var hex: String { String(format: "#%02X%02X%02X", Int((max(0, min(1, red)) * 255).rounded()), Int((max(0, min(1, green)) * 255).rounded()), Int((max(0, min(1, blue)) * 255).rounded())) }

    /// "#RGB", "#RRGGBB" or "#RRGGBBAA" (the # is optional); nil when it is not a colour.
    init?(hex text: String) {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6 || t.count == 8, let v = UInt64(t, radix: 16) else { return nil }
        let full = t.count == 8 ? v : v << 8 | 0xFF
        self.init(red: Double(full >> 24 & 0xFF) / 255, green: Double(full >> 16 & 0xFF) / 255, blue: Double(full >> 8 & 0xFF) / 255, alpha: Double(full & 0xFF) / 255)
    }

    var hsb: (h: Double, s: Double, b: Double) {
        let c = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        return (c.hueComponent, c.saturationComponent, c.brightnessComponent)
    }

    /// Same saturation, brightness and alpha, hue turned by `degrees`.
    func rotated(_ degrees: Double) -> CodableColor {
        let (h, s, b) = hsb
        let n = NSColor(hue: ((h + degrees / 360).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1), saturation: s, brightness: b, alpha: 1).usingColorSpace(.sRGB) ?? .black
        return CodableColor(red: n.redComponent, green: n.greenComponent, blue: n.blueComponent, alpha: alpha)
    }

    /// Complement, triad and analogous neighbours.
    var harmonies: [(String, CodableColor)] {
        [("Complementary", rotated(180)), ("Triad", rotated(120)), ("Triad", rotated(240)), ("Analogous", rotated(-30)), ("Analogous", rotated(30))]
    }
}

extension Studio {
    func swapColors() { (color, secondaryColor) = (secondaryColor, color) }

    /// Remembers a painted colour (most recent first, at most 10).
    func rememberColor(_ c: CodableColor) {
        recentColors.removeAll { $0.hex == c.hex }
        recentColors.insert(CodableColor(red: c.red, green: c.green, blue: c.blue, alpha: 1), at: 0)
        if recentColors.count > 10 { recentColors.removeLast(recentColors.count - 10) }
    }
}

/// Hex input, harmonies, recent colours and saved swatches under the colour card.
struct ColorExtras: View {
    @EnvironmentObject private var s: Studio
    @Environment(\.photoTheme) private var theme
    @AppStorage("swatches") private var stored = ""
    @State private var hexText = ""

    private var swatches: [CodableColor] { stored.split(separator: ",").compactMap { CodableColor(hex: String($0)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField("#RRGGBB", text: $hexText).textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                    .padding(6).background(theme.deep.opacity(0.55), in: RoundedRectangle(cornerRadius: 6)).frame(width: 92)
                    .onSubmit { if var c = CodableColor(hex: hexText) { if hexText.count < 8 { c.alpha = s.color.alpha }; s.color = c } }
                    .accessibilityLabel(L("Hex color"))
                Button { s.swapColors() } label: { Image(systemName: "arrow.left.arrow.right") }.buttonStyle(PhotoPress())
                    .help(L("Swap colors · X")).accessibilityLabel(L("Swap colors"))
                Spacer()
                Button { if !swatches.contains(where: { $0.hex == s.color.hex }) { stored = (swatches.map(\.hex) + [s.color.hex]).suffix(24).joined(separator: ",") } } label: { Image(systemName: "plus") }
                    .buttonStyle(PhotoPress()).help(L("Add swatch")).accessibilityLabel(L("Add swatch"))
            }
            label(L("Harmonies"))
            dots(s.color.harmonies.map(\.1), help: s.color.harmonies.map { L($0.0) })
            if !s.recentColors.isEmpty { label(L("Recent")); dots(s.recentColors) }
            if !swatches.isEmpty {
                label(L("Swatches"))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 8), spacing: 5) {
                    ForEach(swatches, id: \.hex) { c in
                        dot(c).contextMenu { Button(L("Remove swatch")) { stored = swatches.filter { $0.hex != c.hex }.map(\.hex).joined(separator: ",") } }
                    }
                }
            }
        }
        .onAppear { hexText = s.color.hex }
        .onChange(of: s.color) { _, c in hexText = c.hex }
    }

    private func label(_ t: String) -> some View { Text(t.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(theme.secondary) }

    private func dots(_ colors: [CodableColor], help: [String] = []) -> some View {
        HStack(spacing: 5) { ForEach(Array(colors.enumerated()), id: \.offset) { i, c in dot(c, help: help.indices.contains(i) ? help[i] : nil) } }
    }

    private func dot(_ c: CodableColor, help: String? = nil) -> some View {
        Button { var n = c; n.alpha = s.color.alpha; s.color = n } label: {
            RoundedRectangle(cornerRadius: 5).fill(c.color).frame(height: 18).frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.outline))
        }.buttonStyle(.plain).help(help.map { "\($0) · \(c.hex)" } ?? c.hex).accessibilityLabel(help ?? c.hex)
    }
}
