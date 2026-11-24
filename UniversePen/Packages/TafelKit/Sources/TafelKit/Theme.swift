import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

/// The look both apps use: an accent colour (presets or the system colour picker) and an optional
/// flowing background whose colours slowly drift. Stored per device in UserDefaults.
public final class Theme: ObservableObject, @unchecked Sendable {
    public static let shared = Theme()
    public static let defaultAccentHex = "7FE3D3"

    /// Ready-made accents (hex, sRGB). The first one is the UniversePen default.
    public static let presets: [String] = ["7FE3D3", "7CC4FF", "C08BFF", "FF7EB6", "FF8A7A", "FFC46B", "B6F06A", "F2F2F7"]

    @Published public var accentHex: String { didSet { save(); rebuild() } }
    /// Flowing, colour-shifting background instead of the still gradient.
    @Published public var flow: Bool { didSet { save() } }
    /// 0.25 … 2: how fast the background flows and the hues drift.
    @Published public var flowSpeed: Double { didSet { save() } }
    /// Hold the flowing background still (same colours, no redraws) – e.g. on the Mac while an
    /// iPad is connected: an animated window would be redrawn and re-encoded 30 times a second.
    @Published public var flowPaused = false

    /// Derived colours (rebuilt when the accent changes).
    public private(set) var palette = Palette()

    public struct Palette {
        public var accent = Color(red: 0x7F / 255, green: 0xE3 / 255, blue: 0xD3 / 255)
        public var accentBright = Color(red: 0xBF / 255, green: 0xF5 / 255, blue: 0xEC / 255)
        public var second = Color(red: 0xC0 / 255, green: 0x8B / 255, blue: 0xFF / 255)
        public var top = Color(red: 0x3A / 255, green: 0x2F / 255, blue: 0x7A / 255)
        public var mid = Color(red: 0x17 / 255, green: 0x1A / 255, blue: 0x3F / 255)
        public var deep = Color(red: 0x08 / 255, green: 0x0A / 255, blue: 0x1C / 255)
        /// Hues (0…1) for the flowing background.
        var accentHue = 0.475
        var accentSat = 0.44
        var baseHue = 0.68
    }

    private init() {
        let d = UserDefaults.standard
        accentHex = Theme.cleanHex(d.string(forKey: "themeAccent")) ?? Theme.defaultAccentHex
        flow = d.bool(forKey: "themeFlow")
        flowSpeed = d.object(forKey: "themeFlowSpeed") as? Double ?? 1
        rebuild()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(accentHex, forKey: "themeAccent")
        d.set(flow, forKey: "themeFlow")
        d.set(flowSpeed, forKey: "themeFlowSpeed")
    }

    /// Binding-friendly accent as a SwiftUI colour (for ColorPicker).
    public var accent: Color {
        get { palette.accent }
        set { if let h = Theme.hex(of: newValue), h != accentHex { accentHex = h } }
    }

    private func rebuild() {
        guard accentHex.uppercased() != Theme.defaultAccentHex else { palette = Palette(); objectWillChange.send(); return }
        let (r, g, b) = Theme.rgb(accentHex)
        let c = PlatformColor(red: r, green: g, blue: b, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let hue = Double(h), sat = Double(s)
        // Same relation as the brand colours: background hue sits 0.205 above the accent's.
        let base = (hue + 0.205).truncatingRemainder(dividingBy: 1)
        // Grey accents get a neutral, slightly blue night background.
        let bgSat = sat < 0.12 ? 0.25 : 1.0
        var p = Palette()
        p.accent = Color(red: r, green: g, blue: b)
        p.accentBright = Color(red: (r + 1) / 2, green: (g + 1) / 2, blue: (b + 1) / 2)
        p.second = Color(hue: (hue + 0.22).truncatingRemainder(dividingBy: 1), saturation: max(sat, 0.35) * 0.9, brightness: 1)
        p.top = Color(hue: base, saturation: 0.62 * bgSat, brightness: 0.48)
        p.mid = Color(hue: base, saturation: 0.64 * bgSat, brightness: 0.25)
        p.deep = Color(hue: base, saturation: 0.7 * bgSat, brightness: 0.11)
        p.accentHue = hue
        p.accentSat = sat
        p.baseHue = base
        palette = p
        objectWillChange.send()
    }

    // MARK: Hex

    static func cleanHex(_ s: String?) -> String? {
        guard var s = s?.trimmingCharacters(in: .whitespaces).uppercased() else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        return s.count == 6 && UInt32(s, radix: 16) != nil ? s : nil
    }

    static func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
        let v = UInt32(cleanHex(hex) ?? defaultAccentHex, radix: 16) ?? 0
        return (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
    }

    public static func color(_ hex: String) -> Color {
        let (r, g, b) = rgb(hex)
        return Color(red: r, green: g, blue: b)
    }

    public static func hex(of color: Color) -> String? {
        #if canImport(UIKit)
        let c = UIColor(color)
        #else
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        #endif
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

/// Background of both apps: the still brand gradient, or a slowly flowing mesh whose hues drift.
public struct ThemeBackground: View {
    @ObservedObject private var theme = Theme.shared
    @State private var clock = FlowClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}

    public var body: some View {
        // "Reduce Motion": keep the colours, stop the movement.
        if theme.flow && (theme.flowPaused || reduceMotion) {
            let t = clock.phase
            MeshGradient(width: 3, height: 3, points: Self.points(t), colors: Self.colors(t, theme.palette))
        } else if theme.flow {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let t = clock.advance(to: ctx.date, speed: theme.flowSpeed)
                MeshGradient(width: 3, height: 3, points: Self.points(t), colors: Self.colors(t, theme.palette))
            }
        } else {
            Brand.background
        }
    }

    /// Animation time that only moves forward at the current speed, so changing the speed never
    /// jumps to another point of the animation (which would just look like other colours).
    final class FlowClock {
        private var last: Date?
        private(set) var phase = 0.0
        func advance(to now: Date, speed: Double) -> Double {
            if let last { phase += min(max(now.timeIntervalSince(last), 0), 0.25) * speed }
            last = now
            return phase
        }
    }

    /// Inner and edge points wander; corners stay put so the mesh always fills the view.
    static func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ base: Double, _ amp: Double, _ f: Double, _ ph: Double) -> Float { Float(base + amp * sin(t * f + ph)) }
        return [
            [0, 0], [w(0.5, 0.3, 0.9, 0), 0], [1, 0],
            [0, w(0.5, 0.32, 0.7, 1.3)], [w(0.5, 0.3, 1.1, 2.1), w(0.5, 0.3, 0.8, 0.4)], [1, w(0.5, 0.32, 0.6, 2.7)],
            [0, 1], [w(0.5, 0.3, 0.75, 3.6), 1], [1, 1],
        ]
    }

    static func colors(_ t: Double, _ p: Theme.Palette) -> [Color] {
        // Hues drift back and forth around the accent / background hues; bright accent patches
        // pulse and swap places so the flow is easy to see.
        let drift = 0.12 * sin(t * 0.35)
        func hue(_ h: Double) -> Double { ((h + drift).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) }
        func pulse(_ f: Double, _ ph: Double) -> Double { 0.5 + 0.5 * sin(t * f + ph) }
        let s = max(p.accentSat, 0.35)
        let base = p.baseHue
        return [
            Color(hue: hue(base), saturation: 0.6, brightness: 0.42 + 0.14 * pulse(0.5, 0)),
            Color(hue: hue(p.accentHue + 0.22), saturation: s * 0.85, brightness: 0.2 + 0.32 * pulse(0.6, 1)),
            Color(hue: hue(base + 0.06), saturation: 0.62, brightness: 0.3),
            Color(hue: hue(p.accentHue), saturation: s, brightness: 0.18 + 0.34 * pulse(0.55, 2.2)),
            Color(hue: hue(base - 0.04), saturation: 0.66, brightness: 0.2 + 0.1 * pulse(0.4, 3)),
            Color(hue: hue(p.accentHue + 0.1), saturation: s * 0.9, brightness: 0.16 + 0.3 * pulse(0.65, 4.1)),
            Color(hue: hue(base), saturation: 0.7, brightness: 0.1),
            Color(hue: hue(p.accentHue - 0.06), saturation: s * 0.9, brightness: 0.12 + 0.24 * pulse(0.5, 5)),
            Color(hue: hue(base + 0.03), saturation: 0.7, brightness: 0.07),
        ]
    }
}

/// Colour settings (shared by both apps): accent presets, the system colour picker and the
/// flowing background.
public struct ThemeChoice: View {
    @ObservedObject private var theme = Theme.shared
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Theme.presets, id: \.self) { hex in
                    let on = theme.accentHex.uppercased() == hex
                    Button {
                        withAnimation(Brand.spring) { theme.accentHex = hex }
                    } label: {
                        Circle()
                            .fill(Theme.color(hex))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white.opacity(on ? 0.95 : 0.15), lineWidth: on ? 3 : 1))
                            .scaleEffect(on ? 1.12 : 1)
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker(selection: Binding(get: { theme.accent }, set: { theme.accent = $0 }), supportsOpacity: false) {
                    EmptyView()
                }
                .labelsHidden()
            }
            Toggle(L("Fließender Hintergrund"), isOn: $theme.flow.animation(Brand.spring))
                .tint(Brand.mint)
                #if os(macOS)
                .toggleStyle(.switch)
                #endif
            if theme.flow {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Geschwindigkeit")).font(.caption).foregroundStyle(.secondary)
                    Slider(value: $theme.flowSpeed, in: 0.25...2).tint(Brand.mint)
                }
                ThemeBackground()
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1)))
                    .transition(.opacity)
            }
        }
    }
}
