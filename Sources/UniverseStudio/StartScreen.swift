import SwiftUI
import UniversePenHost

/// The parts of UniverseStudio. Only modules that actually work are listed here.
enum StudioModule: String, CaseIterable, Identifiable {
    case photo, pen
    var id: String { rawValue }
    var title: String { switch self { case .photo: "Photo"; case .pen: "UniversePen" } }
    var symbol: String { switch self { case .photo: "camera.aperture"; case .pen: "applepencil.tip" } }
    var summary: String { switch self {
        case .photo: "Paint, retouch and animate in layers."
        case .pen: "Your iPad and Pencil as a drawing tablet and second screen for the Mac."
    } }
}

extension Studio {
    /// Goes to the start screen; open documents stay open.
    func showStartScreen() { module = nil }
    func enter(_ m: StudioModule) { module = m }
}

/// Switches between the start screen and the chosen module.
struct StudioRoot: View {
    @EnvironmentObject var s: Studio
    @AppStorage(ModuleSettings.setupKey) private var setupDone = false
    var body: some View {
        Group {
            if !setupDone { FirstRunSetup() } else {
            switch s.module {
            case .photo: Workspace()
            case .pen: PenModuleView()
            case nil: StartScreen()
            }
            }
        }.animation(PhotoMotion.panel, value: s.module).animation(PhotoMotion.panel, value: setupDone)
    }
}

struct StartScreen: View {
    @EnvironmentObject var s: Studio
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("photoAccent") private var accent = "mint"
    @AppStorage("startScreenAtLaunch") private var atLaunch = true
    @AppStorage(ModuleSettings.key) private var modulesRaw = "photo"
    @AppStorage(ModuleSettings.setupKey) private var setupDone = false
    @ObservedObject private var pen = PenHost.shared
    @Environment(\.colorScheme) private var systemScheme
    @ObservedObject private var localization = Localization.shared
    private var theme: PhotoTheme { PhotoTheme(isDark: appearance == "dark" || (appearance == "system" && systemScheme == .dark), accent: PhotoTheme.accent(accent)) }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)
            HStack(spacing: 14) {
                PhotoMark().scaleEffect(1.4).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("UniverseStudio").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(L("YOUR CREATIVE STUDIO")).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(theme.secondary)
                }
            }
            Text(L("Choose what you want to make.")).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(theme.secondary)
            HStack(alignment: .top, spacing: 16) { ForEach(ModuleSettings.enabled(modulesRaw)) { moduleCard($0) } }
            Text(L("More modules (vector, 3D, video) appear here once they really work.")).font(.system(size: 11)).foregroundStyle(theme.secondary.opacity(0.8))
            Spacer(minLength: 20)
            HStack(spacing: 18) {
                Toggle(L("Show start screen at launch"), isOn: $atLaunch).toggleStyle(.checkbox)
                Button(L("Set up modules…")) { setupDone = false }.buttonStyle(.link)
            }.font(.system(size: 11)).foregroundStyle(theme.secondary).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .background(PhotoAmbient())
        .foregroundStyle(theme.text)
        .environment(\.photoTheme, theme)
        .tint(theme.accent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        // Menu commands that need a document go straight into the photo module.
        .onChange(of: s.showNewDocument) { if s.showNewDocument { s.enter(.photo) } }
        .onChange(of: s.tabs.count) { s.enter(.photo) }
        .onChange(of: s.commandSearch) { if s.commandSearch { s.enter(.photo) } }
        .onChange(of: s.showShortcuts) { if s.showShortcuts { s.enter(.photo) } }
        .onChange(of: s.undoStack.count) { s.enter(.photo) }
    }

    private func moduleCard(_ m: StudioModule) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { s.enter(m) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: m.symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(theme.accent)
                    Text(L(m.title)).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(L(m.summary)).font(.system(size: 12)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(PhotoPress())
            HStack(spacing: 8) {
                switch m {
                case .photo:
                    Button(L("New document…")) { s.enter(m); s.showNewDocument = true }.buttonStyle(PhotoButtonStyle(prominent: true))
                    Button(L("Open…")) { s.openPanel() }.buttonStyle(PhotoButtonStyle())
                    Button(L("Continue")) { s.enter(m) }.buttonStyle(PhotoButtonStyle())
                case .pen:
                    Button(L("Open")) { s.enter(m) }.buttonStyle(PhotoButtonStyle(prominent: true))
                    if pen.running { Button(L("Pair iPad…")) { s.enter(m); UniversePenModule.beginPairing() }.buttonStyle(PhotoButtonStyle()) }
                }
            }
            if m == .pen {
                Label(pen.running ? L("Running – also in the menu bar") : pen.standaloneRunning ? L("Old UniversePen Host app still running") : L("Not running"),
                      systemImage: pen.running ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(pen.running ? theme.accent : theme.secondary)
            }
        }
        .photoCard(padding: 20)
        .frame(width: 340)
    }
}
