import SwiftUI
import TafelKit

/// First-run setup on the Mac: language, permissions, default source, pairing.
struct HostOnboarding: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var host: HostController
    @ObservedObject private var l10n = L10n.shared
    @Binding var done: Bool
    /// `-debugHostOnboardingStep N` opens a step directly (UI checks).
    @State private var step = UserDefaults.standard.integer(forKey: "debugHostOnboardingStep")
    @State private var forward = true
    @State private var pairedAtStart: String?

    private let steps = 5
    private var allGranted: Bool { host.screenRecordingGranted && host.accessibilityGranted }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36).padding(.top, 30)
            .clipped()
            footer
        }
        .frame(width: 600, height: 600)
        .background(ThemeBackground())
        .preferredColorScheme(.dark)
        .tint(Brand.mint)
        .animation(Ultra.smooth, value: step)
        .animation(Ultra.smooth, value: allGranted)
        .animation(Ultra.smooth, value: host.pairingCode)
        .animation(Ultra.smooth, value: host.lastPaired)
        .animation(Ultra.smooth, value: host.mode)
        .sensoryFeedback(.selection, trigger: step)
        .onAppear { pairedAtStart = host.lastPaired }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0: language
        case 1: welcome
        case 2: permissions
        case 3: source
        default: pairing
        }
    }

    private var footer: some View {
        HStack {
            Button { go(-1) } label: {
                Label(L("Zurück"), systemImage: "chevron.left")
            }
            .buttonStyle(UltraQuiet(compact: true))
            .opacity(step == 0 ? 0 : 1)
            .disabled(step == 0)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? AnyShapeStyle(Ultra.accentFill) : AnyShapeStyle(Color.white.opacity(i < step ? 0.45 : 0.2)))
                        .frame(width: i == step ? 24 : 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Schritt %d von %d", step + 1, steps))
            Spacer()
            Button {
                if step == steps - 1 { host.endPairing(); done = true } else { go(1) }
            } label: {
                HStack(spacing: 7) {
                    Text(step == steps - 1 ? L("Fertig") : L("Weiter"))
                    Image(systemName: step == steps - 1 ? "checkmark" : "arrow.right")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(UltraProminent(compact: true))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24).padding(.top, 8)
    }

    private func go(_ d: Int) {
        forward = d > 0
        step = max(0, min(steps - 1, step + d))
    }

    // MARK: Pages

    private var language: some View {
        StepPage(symbol: "globe", title: "Language · Sprache", subtitle: "Choose your language. · Wähle deine Sprache.") {
            LanguageChoice()
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                PulseRings(color: Brand.mint).frame(width: 150, height: 150)
                TafelMark().frame(width: 100, height: 100).shadow(color: Brand.mint.opacity(0.45), radius: 26)
            }
            Text(L("Willkommen bei UniversePen")).font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(L("UniversePen macht dein iPad zum Zeichendisplay für diesen Mac – per USB-Kabel oder WLAN, verschlüsselt und ohne Cloud. In drei Schritten ist alles eingerichtet."))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var permissions: some View {
        StepPage(symbol: "lock.shield", title: L("Zwei Berechtigungen"),
                 subtitle: L("macOS fragt einmal nach. Danach bleibt es so – auch nach Updates von UniversePen.")) {
            UltraSection {
                permissionRow(L("Bildschirmaufnahme"), "rectangle.dashed.badge.record", L("Damit das Bild aufs iPad kommt."),
                              host.screenRecordingGranted, host.requestScreenRecording)
                permissionRow(L("Bedienungshilfen"), "accessibility", L("Damit Stift, Finger, Maus und Tastatur am Mac ankommen."),
                              host.accessibilityGranted, host.requestAccessibility)
            }
            if allGranted {
                Label(L("Alles erlaubt."), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Brand.mintBright).font(.headline)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(L("Nach dem Erlauben in den Systemeinstellungen springt das Häkchen hier von selbst um. Bei der Bildschirmaufnahme kann macOS einen Neustart von UniversePen Host verlangen."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionRow(_ title: String, _ symbol: String, _ detail: String, _ granted: Bool, _ action: @escaping () -> Void) -> some View {
        SettingRow(symbol: symbol, title: title, detail: detail) {
            if granted {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Brand.mint)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(L("Erlauben …"), action: action).buttonStyle(UltraProminent(compact: true))
            }
        }
    }

    private var source: some View {
        StepPage(symbol: "rectangle.dashed.badge.record", title: L("Was soll aufs iPad?"),
                 subtitle: L("Lässt sich jederzeit im UniversePen-Fenster umstellen.")) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(CaptureMode.allCases) { m in
                    let unavailable = m == .virtual && !HostController.secondScreenAvailable
                    UltraTile(m.title, symbol: m.symbol, on: host.mode == m, enabled: !unavailable, minHeight: 74) { host.mode = m }
                }
            }
            Text(host.mode.help).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }

    private var pairing: some View {
        StepPage(symbol: "ipad.and.arrow.forward", title: L("iPad koppeln"),
                 subtitle: L("Öffne UniversePen auf dem iPad, tippe unter „Neu koppeln“ auf diesen Mac und gib den Code ein.")) {
            if let paired = host.lastPaired, paired != pairedAtStart {
                Label(L("%@ ist gekoppelt.", paired), systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.semibold)).foregroundStyle(Brand.mintBright)
                    .ultraCard()
                    .transition(.scale.combined(with: .opacity))
            } else if let code = host.pairingCode {
                PairingCodeView(code: code, seconds: host.pairingSecondsLeft)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .ultraCard()
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                Button { host.beginPairing() } label: {
                    Label(L("Code anzeigen"), systemImage: "key.horizontal")
                }
                .buttonStyle(UltraProminent())
            }
            Text(L("Schon gekoppelt? Dann einfach „Fertig“ – das iPad verbindet sich von selbst."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One step: accent badge, title, subtitle, then the content arriving a beat later.
private struct StepPage<Content: View>: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                UltraBadge(symbol, size: 58)
                    .symbolEffect(.bounce, value: shown)
                    .scaleEffect(shown ? 1 : 0.6)
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 14) { content }
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
        .onAppear { withAnimation(Ultra.bouncy.delay(0.1)) { shown = true } }
    }
}
