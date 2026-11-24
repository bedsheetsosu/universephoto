import SwiftUI
import UniversePenHost

/// First-run setup: pick the modules you want, then each chosen module sets itself up.
/// Shown until finished once; "Set up modules…" on the start screen opens it again.
struct FirstRunSetup: View {
    enum Step: Hashable { case welcome, photo, pen, done }
    @EnvironmentObject var s: Studio
    @AppStorage(ModuleSettings.key) private var modulesRaw = "photo"
    @AppStorage(ModuleSettings.setupKey) private var setupDone = false
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("photoAccent") private var accent = "mint"
    @AppStorage("documentBackground") private var background = "white"
    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var pen = PenHost.shared
    @Environment(\.colorScheme) private var systemScheme
    @State private var chosen: Set<StudioModule> = []
    @State private var step: Step = .welcome
    @State private var penSetupDone = false

    private var theme: PhotoTheme { PhotoTheme(isDark: appearance == "dark" || (appearance == "system" && systemScheme == .dark), accent: PhotoTheme.accent(accent)) }
    /// The steps for the chosen modules, in a fixed order.
    var steps: [Step] { Self.steps(for: chosen) }
    static func steps(for chosen: Set<StudioModule>) -> [Step] {
        [.welcome] + (chosen.contains(.photo) ? [.photo] : []) + (chosen.contains(.pen) ? [.pen] : []) + [.done]
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .photo: photoSetup
                case .pen: penSetup
                case .done: finished
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            if step != .pen || !pen.running { footer }
        }
        .background(PhotoAmbient())
        .foregroundStyle(theme.text)
        .environment(\.photoTheme, theme)
        .tint(theme.accent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .animation(PhotoMotion.panel, value: step)
        .onAppear {
            chosen = Set(ModuleSettings.enabled(modulesRaw))
            // Someone who used the stand-alone UniversePen Host gets it ticked already.
            if UserDefaults.standard.string(forKey: ModuleSettings.key) == nil, UserDefaults.standard.persistentDomain(forName: UniversePenModule.standaloneBundleID) != nil { chosen.insert(.pen) }
        }
        .onChange(of: penSetupDone) { if penSetupDone { advance() } }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                PhotoMark().scaleEffect(1.4).frame(width: 52, height: 52)
                Text(L("Welcome to UniverseStudio")).font(.system(size: 28, weight: .bold, design: .rounded))
            }
            Picker(L("Language"), selection: $localization.language) { Text("English").tag("en"); Text("Deutsch").tag("de") }
                .pickerStyle(.segmented).frame(width: 220).labelsHidden()
            Text(L("Which parts do you want to use? You can change this later on the start screen.")).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
            HStack(alignment: .top, spacing: 16) {
                ForEach(StudioModule.allCases) { m in
                    let on = chosen.contains(m)
                    Button { if on { chosen.remove(m) } else { chosen.insert(m) } } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Image(systemName: m.symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(theme.accent); Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(on ? theme.accent : theme.secondary) }
                            Text(L(m.title)).font(.system(size: 19, weight: .bold, design: .rounded))
                            Text(L(m.summary)).font(.system(size: 12)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(PhotoPress()).accessibilityAddTraits(on ? .isSelected : [])
                    .photoCard(padding: 20).frame(width: 290)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? theme.accent : .clear, lineWidth: 1.5))
                }
            }
        }.padding(30)
    }

    private var photoSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            header(.photo, L("Set up Photo"))
            row(L("Appearance")) { Picker("", selection: $appearance) { Text(L("Dark")).tag("dark"); Text(L("Light")).tag("light"); Text(L("System")).tag("system") }.pickerStyle(.segmented).frame(width: 260) }
            row(L("Accent")) {
                HStack(spacing: 10) { ForEach(PhotoTheme.accentKeys, id: \.self) { k in
                    Button { accent = k } label: { Circle().fill(PhotoTheme.accent(k)).frame(width: 24, height: 24).overlay(Circle().strokeBorder(.white, lineWidth: accent == k ? 2.5 : 0)) }.buttonStyle(.plain).help(k)
                } }
            }
            row(L("New documents")) { Picker("", selection: $background) { Text(L("White")).tag("white"); Text(L("Transparent")).tag("transparent") }.pickerStyle(.segmented).frame(width: 260) }
            row(L("Pen pressure")) { Toggle(L("Pressure controls opacity"), isOn: $s.pressureOpacity).toggleStyle(.checkbox) }
        }.frame(width: 560).padding(30)
    }

    @ViewBuilder private var penSetup: some View {
        if pen.running {
            // The host's own setup: language, permissions, source, pairing.
            UniversePenModule.setupView(done: $penSetupDone)
        } else {
            VStack(spacing: 16) { header(.pen, L("Set up UniversePen")); PenWaitingView() }.frame(width: 560).padding(30)
        }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 46)).foregroundStyle(theme.accent)
            Text(L("All set")).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(L("Your modules are on the start screen. Set up modules… there brings you back here.")).foregroundStyle(theme.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome { Button(L("Back")) { back() }.buttonStyle(PhotoButtonStyle()) }
            Spacer()
            if step == .pen { Button(L("Skip")) { advance() }.buttonStyle(PhotoButtonStyle()) }
            Button(step == .done ? L("Start") : L("Next")) { advance() }.buttonStyle(PhotoButtonStyle(prominent: true))
                .disabled(step == .welcome && chosen.isEmpty).keyboardShortcut(.defaultAction)
        }.padding(.horizontal, 30).padding(.bottom, 24)
    }

    private func header(_ m: StudioModule, _ title: String) -> some View {
        HStack(spacing: 10) { Image(systemName: m.symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.accent); Text(title).font(.system(size: 24, weight: .bold, design: .rounded)) }
    }
    private func row<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack { Text(title).frame(width: 150, alignment: .leading).foregroundStyle(theme.secondary); c(); Spacer(minLength: 0) }
    }

    // MARK: Navigation

    private func advance() {
        if step == .welcome {
            modulesRaw = ModuleSettings.store(chosen)
            PenHost.shared.startIfWanted()
        }
        if step == .done { setupDone = true; s.module = nil; return }
        let all = steps
        if let i = all.firstIndex(of: step), i + 1 < all.count { step = all[i + 1] }
    }
    private func back() {
        let all = steps
        if let i = all.firstIndex(of: step), i > 0 { step = all[i - 1] }
    }
}
