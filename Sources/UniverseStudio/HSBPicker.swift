import AppKit
import SwiftUI

/// Direct colour choice in the Colors card: a saturation/brightness field for the current hue and
/// a hue strip below it. Dragging sets the foreground colour live (alpha stays).
struct HSBPicker: View {
    @EnvironmentObject private var s: Studio
    @Environment(\.photoTheme) private var theme
    /// The hue is kept here so it survives grey colours (where the colour itself has none).
    @State private var hue = 0.0
    @State private var dragging = false

    static func color(h: Double, s sat: Double, b: Double, alpha: Double) -> CodableColor {
        let n = NSColor(hue: max(0, min(1, h)), saturation: max(0, min(1, sat)), brightness: max(0, min(1, b)), alpha: 1).usingColorSpace(.sRGB) ?? .black
        return CodableColor(red: n.redComponent, green: n.greenComponent, blue: n.blueComponent, alpha: alpha)
    }

    var body: some View {
        let hsb = s.color.hsb
        VStack(spacing: 8) {
            GeometryReader { g in
                ZStack {
                    LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    Circle().strokeBorder(.white, lineWidth: 2).shadow(color: .black.opacity(0.5), radius: 1.5).frame(width: 13, height: 13)
                        .position(x: hsb.s * g.size.width, y: (1 - hsb.b) * g.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.outline))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let sat = v.location.x / max(1, g.size.width), b = 1 - v.location.y / max(1, g.size.height)
                    s.color = Self.color(h: hue, s: sat, b: b, alpha: s.color.alpha)
                })
            }.frame(height: 96)
                .accessibilityElement().accessibilityLabel(L("Saturation and brightness"))
                .accessibilityValue("\(Int(hsb.s * 100)) %, \(Int(hsb.b * 100)) %")
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    LinearGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing)
                        .clipShape(Capsule()).overlay(Capsule().strokeBorder(theme.outline))
                    Circle().fill(Color(hue: hue, saturation: 1, brightness: 1)).overlay(Circle().strokeBorder(.white, lineWidth: 2)).shadow(color: .black.opacity(0.4), radius: 1.5)
                        .frame(width: 14, height: 14).offset(x: hue * (g.size.width - 14))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    hue = max(0, min(1, v.location.x / max(1, g.size.width)))
                    dragging = true
                    s.color = Self.color(h: hue, s: hsb.s, b: hsb.b, alpha: s.color.alpha)
                }.onEnded { _ in dragging = false })
            }.frame(height: 14)
                .accessibilityElement().accessibilityLabel(L("Hue")).accessibilityValue("\(Int(hue * 360))°")
                .accessibilityAdjustableAction { d in hue = max(0, min(1, hue + (d == .increment ? 1 : -1) / 36)); s.color = Self.color(h: hue, s: hsb.s, b: hsb.b, alpha: s.color.alpha) }
        }
        .onAppear { if hsb.s > 0.01 { hue = hsb.h } }
        .onChange(of: s.color) { if !dragging, s.color.hsb.s > 0.01, s.color.hsb.b > 0.01 { hue = s.color.hsb.h } }
    }
}
