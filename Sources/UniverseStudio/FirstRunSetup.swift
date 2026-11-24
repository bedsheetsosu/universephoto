import SwiftUI
import UniversePenHost

/// First-run setup: pick the modules you want, then each chosen module sets itself up.
/// Shown until finished once; "Set up modules…" on the start screen opens it again.
/// Motion follows UniversePen's setup: pages slide in the direction you go, the badge bounces,
/// the content rises a beat later, the progress capsule stretches to the current step.
struct FirstRunSetup: View {
    enum Step: Hashable { case welcome, modules, photo, pen, done }
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
    @State private var forward = true
    @State private var penSetupDone = false

    private var theme: PhotoTheme { PhotoTheme(isDark: appearance == "dark" || (appearance == "system" && systemScheme == .dark), accent: PhotoTheme.accent(accent)) }
    var steps: [Step] { Self.steps(for: chosen) }
    /// The steps for the chosen modules, in a fixed order.
    static func steps(for chosen: Set<StudioModule>) -> [Step] {
        [.welcome, .modules] + (chosen.contains(.photo) ? [.photo] : []) + (chosen.contains(.pen) ? [.pen] : []) + [.done]
    }
    /// UniversePen brings its own setup with its own buttons.
    private var hostSetupShown: Bool { step == .pen && pen.running }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack {
                    page
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, hostSetupShown ? 0 : 36).padding(.top, hostSetupShown ? 0 : 30)
                .clipped()
                if !hostSetupShown { footer.transition(.opacity) }
            }
            // UniversePen's own setup is 600 × 600 with its own background: the panel takes its size.
            .frame(width: hostSetupShown ? 600 : 640, height: hostSetupShown ? 600 : 640)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .photoChrome(radius: 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhotoAmbient())
        .foregroundStyle(theme.text)
        .environment(\.photoTheme, theme)
        .tint(theme.accent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .animation(SetupMotion.smooth, value: step)
        .animation(SetupMotion.smooth, value: chosen)
        .animation(SetupMotion.smooth, value: pen.running)
        .animation(SetupMotion.smooth, value: hostSetupShown)
        .animation(SetupMotion.smooth, value: accent)
        .sensoryFeedback(.selection, trigger: step)
        .onAppear {
            chosen = Set(ModuleSettings.enabled(modulesRaw))
            // Someone who used the stand-alone UniversePen Host gets it ticked already.
            if UserDefaults.standard.string(forKey: ModuleSettings.key) == nil, UserDefaults.standard.persistentDomain(forName: UniversePenModule.standaloneBundleID) != nil { chosen.insert(.pen) }
        }
        .onChange(of: penSetupDone) { if penSetupDone { go(1) } }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome: welcome
        case .modules: modules
        case .photo: photoSetup
        case .pen: penSetup
        case .done: finished
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                SetupPulse(color: theme.accent).frame(width: 170, height: 170)
                PhotoMark().scaleEffect(2.6).frame(width: 92, height: 92).shadow(color: theme.accent.opacity(0.45), radius: 26)
            }
            Text(L("Welcome to UniverseStudio")).font(.system(size: 30, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
            Text(L("Photo editing and your iPad as a drawing tablet, in one app. A few steps and everything is set up.")).multilineTextAlignment(.center).foregroundStyle(theme.secondary).frame(maxWidth: 430)
            Picker(L("Language"), selection: $localization.language) { Text("English").tag("en"); Text("Deutsch").tag("de") }
                .pickerStyle(.segmented).frame(width: 220).labelsHidden().padding(.top, 6)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var modules: some View {
        SetupPage(symbol: "square.grid.2x2", title: L("What do you want to use?"), subtitle: L("Which parts do you want to use? You can change this later on the start screen.")) {
            ForEach(Array(StudioModule.allCases.enumerated()), id: \.element) { i, m in
                ModuleTile(module: m, on: chosen.contains(m), delay: Double(i) * 0.07) {
                    if chosen.contains(m) { chosen.remove(m) } else { chosen.insert(m) }
                }
            }
            if chosen.isEmpty {
                Text(L("Pick at least one.")).font(.caption).foregroundStyle(theme.secondary).transition(.opacity)
            }
        }
    }

    private var photoSetup: some View {
        SetupPage(symbol: StudioModule.photo.symbol, title: L("Set up Photo"), subtitle: L("How the studio looks and how new documents start. All of it is in the settings later, too.")) {
            VStack(spacing: 0) {
                row(L("Appearance"), "circle.lefthalf.filled") { Picker("", selection: $appearance) { Text(L("Dark")).tag("dark"); Text(L("Light")).tag("light"); Text(L("System")).tag("system") }.pickerStyle(.segmented).labelsHidden().frame(width: 230) }
                Divider().opacity(0.4)
                row(L("Accent"), "paintpalette") {
                    HStack(spacing: 9) { ForEach(PhotoTheme.accentKeys, id: \.self) { k in
                        Button { accent = k } label: {
                            Circle().fill(PhotoTheme.accent(k)).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.white, lineWidth: accent == k ? 2.5 : 0))
                                .scaleEffect(accent == k ? 1.15 : 1)
                        }.buttonStyle(.plain).accessibilityLabel(k).accessibilityAddTraits(accent == k ? .isSelected : [])
                    } }
                }
                Divider().opacity(0.4)
                row(L("New documents"), "doc") { Picker("", selection: $background) { Text(L("White")).tag("white"); Text(L("Transparent")).tag("transparent") }.pickerStyle(.segmented).labelsHidden().frame(width: 230) }
                Divider().opacity(0.4)
                row(L("Pen pressure"), "applepencil.tip") { Toggle(L("Pressure controls opacity"), isOn: $s.pressureOpacity).toggleStyle(.switch).controlSize(.small) }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .photoCard(padding: 0)
        }
    }

    @ViewBuilder private var penSetup: some View {
        if pen.running {
            // UniversePen's own setup: language, permissions, source, pairing.
            UniversePenModule.setupView(done: $penSetupDone, back: { go(-1) })
        } else {
            SetupPage(symbol: StudioModule.pen.symbol, title: L("Set up UniversePen"), subtitle: L("UniverseStudio now contains UniversePen. Both cannot run at the same time; quit the old app to use it here.")) {
                PenWaitingView().frame(maxWidth: .infinity).photoCard(padding: 18)
            }
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                SetupPulse(color: theme.accent).frame(width: 150, height: 150)
                SetupBadge(symbol: "checkmark", size: 84, bounce: true)
            }
            Text(L("All set")).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(L("Your modules are on the start screen. Set up modules… there brings you back here.")).multilineTextAlignment(.center).foregroundStyle(theme.secondary).frame(maxWidth: 420)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        let all = steps, index = all.firstIndex(of: step) ?? 0, last = step == .done
        return HStack {
            Button { go(-1) } label: { Label(L("Back"), systemImage: "chevron.left") }
                .buttonStyle(PhotoButtonStyle())
                .opacity(index == 0 ? 0 : 1).disabled(index == 0)
            Spacer()
            HStack(spacing: 7) {
                ForEach(all.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.text.opacity(i < index ? 0.45 : 0.2)))
                        .frame(width: i == index ? 24 : 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LF("Step %d of %d", index + 1, all.count))
            Spacer()
            if step == .pen { Button(L("Skip")) { go(1) }.buttonStyle(PhotoButtonStyle()) }
            Button { go(1) } label: {
                HStack(spacing: 7) {
                    Text(last ? L("Start") : L("Next"))
                    Image(systemName: last ? "checkmark" : "arrow.right").contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(PhotoButtonStyle(prominent: true))
            .disabled(step == .modules && chosen.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28).padding(.bottom, 24).padding(.top, 8)
    }

    private func row<C: View>(_ title: String, _ symbol: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent).frame(width: 22)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 12)
            c()
        }.padding(.vertical, 12)
    }

    // MARK: Navigation

    private func go(_ d: Int) {
        if d > 0 {
            if step == .modules { modulesRaw = ModuleSettings.store(chosen); PenHost.shared.startIfWanted() }
            if step == .done { setupDone = true; s.module = nil; return }
        }
        let all = steps
        guard let i = all.firstIndex(of: step) else { return }
        forward = d > 0
        step = all[max(0, min(all.count - 1, i + d))]
    }
}

/// UniversePen's springs, with the same reduce-motion fallback.
enum SetupMotion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var smooth: Animation { reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86) }
    static var bouncy: Animation { reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.62) }
}

/// One step: accent badge, title, subtitle, then the content arriving a beat later.
private struct SetupPage<Content: View>: View {
    @Environment(\.photoTheme) private var theme
    let symbol: String, title: String, subtitle: String
    @ViewBuilder var content: Content
    @State private var shown = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SetupBadge(symbol: symbol, size: 58, bounce: shown).scaleEffect(shown ? 1 : 0.6)
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 12) { content }
                    .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
        }
        .scrollIndicators(.never)
        .onAppear { withAnimation(SetupMotion.bouncy.delay(0.1)) { shown = true } }
    }
}

/// The accent badge with a glow, like UniversePen's.
private struct SetupBadge: View {
    @Environment(\.photoTheme) private var theme
    let symbol: String; var size: CGFloat = 58; var bounce = false
    @State private var appeared = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(theme.onAccent)
            .frame(width: size, height: size)
            .background(theme.accentGradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .shadow(color: theme.accent.opacity(0.5), radius: size * 0.26, y: size * 0.07)
            .symbolEffect(.bounce, value: bounce || appeared)
            .onAppear { if bounce { appeared = true } }
    }
}

/// Rings that keep breathing out from the centre (paused with reduce motion).
private struct SetupPulse: View {
    var color: Color
    var body: some View {
        TimelineView(.animation(paused: SetupMotion.reduce)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle().strokeBorder(color.opacity(0.55 * (1 - p)), lineWidth: 1.5).scaleEffect(0.55 + p * 0.45)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A module to switch on or off; arrives slightly after the one before it.
private struct ModuleTile: View {
    @Environment(\.photoTheme) private var theme
    let module: StudioModule; let on: Bool; var delay = 0.0
    let toggle: () -> Void
    @State private var shown = false
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: module.symbol).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(on ? theme.onAccent : theme.accent)
                    .frame(width: 46, height: 46)
                    .background(on ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.accent.opacity(0.14)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L(module.title)).font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(L(module.summary)).font(.system(size: 12)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .foregroundStyle(on ? theme.accent : theme.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.edge.opacity(0.32)), lineWidth: on ? 1.5 : 0.7))
            .shadow(color: on ? theme.accent.opacity(0.22) : .clear, radius: 12, y: 4)
            .scaleEffect(on ? 1 : 0.985)
            .contentShape(Rectangle())
        }
        .buttonStyle(PhotoPress())
        .accessibilityAddTraits(on ? .isSelected : [])
        .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 10)
        .onAppear { withAnimation(SetupMotion.bouncy.delay(0.18 + delay)) { shown = true } }
    }
}
