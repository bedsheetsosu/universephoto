import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Shared look of both apps (UniversePen: deep-space indigo, cyan-mint accent, from the icon).
public enum Brand {
    public static var slateTop: Color { Theme.shared.palette.top }
    public static var slate: Color { Theme.shared.palette.mid }
    public static var slateDeep: Color { Theme.shared.palette.deep }
    public static var violet: Color { Theme.shared.palette.second }
    /// Accent colour (default mint; follows the user's choice).
    public static var mint: Color { Theme.shared.palette.accent }
    public static var mintBright: Color { Theme.shared.palette.accentBright }

    public static var background: LinearGradient {
        LinearGradient(colors: [slateTop, slate, slateDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The app's spring – a short plain fade-in-place when "Reduce Motion" is on.
    public static var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.45, dampingFraction: 0.82)
    }

    public static var reduceMotion: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }
}

public extension View {
    /// Liquid Glass where available, a material otherwise.
    @ViewBuilder func tafelGlass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Calm frosted look for controls that float over the live Mac picture. Liquid Glass adapts
    /// its brightness to whatever is behind it, which over moving video looks like pulsing.
    func tafelOverlayGlass<S: Shape>(_ shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .background(Color.black.opacity(0.42), in: shape)
            .overlay(shape.stroke(Ultra.edgeLight, lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }

    /// Rounded card used on both platforms.
    func tafelCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ultraGlass(Ultra.shape(Ultra.cardRadius))
    }
}

/// Expanding rings, e.g. "searching" or "waiting for the iPad".
/// Driven by a timeline (not an implicit repeatForever animation), so it never picks up the
/// position of a sheet or page that is animating in.
public struct PulseRings: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    var color: Color
    var active: Bool

    public init(color: Color = Brand.mint, active: Bool = true) {
        self.color = color
        self.active = active
    }

    public var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { i in
                    let p = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(color.opacity(0.6), lineWidth: 1.5)
                        .scaleEffect(0.6 + 1.3 * p)
                        .opacity(0.9 * (1 - p))
                }
            }
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: active)
        .allowsHitTesting(false)
    }
}

/// Small app mark (slate tile with a stroke), drawn in SwiftUI so it scales crisply.
public struct TafelMark: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    public init() {}
    public var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .fill(Brand.background)
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
                Path { p in
                    p.move(to: CGPoint(x: s * 0.16, y: s * 0.60))
                    p.addCurve(to: CGPoint(x: s * 0.62, y: s * 0.60),
                               control1: CGPoint(x: s * 0.32, y: s * 0.20), control2: CGPoint(x: s * 0.44, y: s * 0.95))
                }
                .stroke(LinearGradient(colors: [.white, Brand.mint, Brand.violet], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: s * 0.065, lineCap: .round))
                .shadow(color: Brand.mint.opacity(0.7), radius: s * 0.05)
                Capsule()
                    .fill(.white)
                    .frame(width: s * 0.36, height: s * 0.075)
                    .rotationEffect(.degrees(-45))
                    .offset(x: s * 0.13, y: -s * 0.02)
                    .shadow(color: .black.opacity(0.4), radius: s * 0.02, y: s * 0.01)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Language tiles (flag + name in its own language). Switching is instant.
public struct LanguageChoice: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @ObservedObject private var l10n = L10n.shared
    public init() {}

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            ForEach(AppLanguage.allCases) { lang in
                let on = l10n.language == lang
                Button {
                    withAnimation(Brand.spring) { l10n.language = lang }
                } label: {
                    VStack(spacing: 8) {
                        Text(lang.flag).font(.system(size: 32))
                        Text(lang.nativeName).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(on ? Brand.slateDeep : .primary)
                    .ultraChoice(Ultra.shape(18), on: on)
                    .scaleEffect(on ? 1.03 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
