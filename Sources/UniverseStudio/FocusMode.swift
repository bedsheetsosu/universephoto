import SwiftUI

/// Focus mode (button next to the logo, View → Focus mode, ⌥⌘F): the window shows only the canvas
/// and the tool options; tools, colours and the inspector move into a separate "Panels" window
/// that can sit anywhere – on a second screen, too. A small pill in the corner leads back.
enum FocusMode {
    static let windowID = "focusPanels"
    static let windowDelay = 0.4
    /// Theme from the stored appearance settings, for windows outside the workspace.
    static func theme(appearance: String, accent: String, systemDark: Bool) -> PhotoTheme {
        PhotoTheme(isDark: appearance == "dark" || (appearance == "system" && systemDark), accent: PhotoTheme.accent(accent))
    }
}

/// Opens and closes the Panels window together with focus mode.
struct FocusWindowSync: ViewModifier {
    @ObservedObject var s: Studio
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    func body(content: Content) -> some View {
        content.onChange(of: s.focusMode) { _, on in
            if on {
                // Opened after the layout animation, so building the window doesn't stall it.
                DispatchQueue.main.asyncAfter(deadline: .now() + FocusMode.windowDelay) { if s.focusMode { openWindow(id: FocusMode.windowID) } }
            } else { dismissWindow(id: FocusMode.windowID) }
        }
    }
}

/// The way back, in the top left corner of the canvas while focus mode is on.
struct FocusPill: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing: 6) {
            PhotoMark().scaleEffect(0.7).frame(width: 25, height: 25)
            Button { openWindow(id: FocusMode.windowID) } label: { Image(systemName: "rectangle.on.rectangle").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain).help(L("Show panels window")).accessibilityLabel(L("Show panels window"))
            Button { withAnimation(PhotoMotion.panel) { s.focusMode = false } } label: {
                Label(L("Exit focus"), systemImage: "arrow.down.right.and.arrow.up.left").font(.system(size: 10, weight: .semibold))
            }.buttonStyle(.plain).help(L("Exit focus") + " · ⌥⌘F")
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
        .photoChrome(radius: 14)
    }
}

/// The separate window: tool grid with colours on top, the inspector below.
struct FocusPanelsWindow: View {
    @EnvironmentObject var s: Studio
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("photoAccent") private var accent = "mint"
    @AppStorage("workspace") private var workspace = "Photo"
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = FocusMode.theme(appearance: appearance, accent: accent, systemDark: systemScheme == .dark)
        VStack(spacing: 10) {
            FocusToolGrid().padding(10).photoChrome(radius: 16)
            InspectorPanel(simple: workspace == "Simple").photoChrome(radius: 16)
        }
        .padding(10)
        .frame(minWidth: 260, idealWidth: 290, minHeight: 420, idealHeight: 760)
        .background(PhotoAmbient())
        .foregroundStyle(theme.text)
        .environment(\.photoTheme, theme)
        .tint(theme.accent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .onChange(of: s.focusMode) { _, on in if !on { dismiss() } }
    }
}

struct FocusToolGrid: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 6), spacing: 4) {
                ForEach(Tool.allCases) { tool in
                    let selected = s.tool == tool
                    Button { withAnimation(PhotoMotion.select) { s.tool = tool } } label: {
                        Image(systemName: tool.symbol).font(.system(size: 14, weight: selected ? .semibold : .regular))
                            .frame(width: 34, height: 31)
                            .foregroundStyle(selected ? theme.onAccent : theme.text.opacity(0.8))
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.card.opacity(0.4))))
                    }
                    .buttonStyle(HoverButtonStyle()).help(L(tool.english) + " · " + tool.key.uppercased())
                    .accessibilityLabel(L(tool.english)).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack(spacing: 8) {
                ColorPicker(L("Foreground"), selection: Binding(get: { s.color.color }, set: { s.color = CodableColor($0) }), supportsOpacity: true).labelsHidden()
                ColorPicker(L("Background"), selection: Binding(get: { s.secondaryColor.color }, set: { s.secondaryColor = CodableColor($0) }), supportsOpacity: true).labelsHidden()
                Button { let old = s.color; s.color = s.secondaryColor; s.secondaryColor = old } label: { Image(systemName: "arrow.left.arrow.right") }
                    .buttonStyle(.plain).help(L("Swap colors")).accessibilityLabel(L("Swap colors"))
                Spacer()
            }
        }
    }
}
