import SwiftUI
import TafelKit

/// Areas of the Mac window.
enum HostPage: String, CaseIterable, Identifiable {
    case overview, source, pairing, stream, general, developer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("Übersicht")
        case .source: return L("Quelle")
        case .pairing: return L("Kopplung")
        case .stream: return L("Übertragung")
        case .general: return L("Allgemein")
        case .developer: return L("Entwickler")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "sparkles.rectangle.stack"
        case .source: return "rectangle.dashed.badge.record"
        case .pairing: return "link"
        case .stream: return "waveform.path.ecg"
        case .general: return "gearshape"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// The Mac window: a glass sidebar floating over the app's background, one calm page at a time.
struct HostView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var host: HostController
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openWindow) private var openWindow
    @AppStorage("hostOnboardingDone") private var onboardingDone = false
    /// Every window starts on the overview: the state of the connection comes first.
    @State private var page = HostPage(rawValue: UserDefaults.standard.string(forKey: "debugHostPage") ?? "") ?? .overview
    @Namespace private var sidebarSpace
    @State private var confirmUnpair = false
    @State private var confirmRemove: DeviceKeyStore.Device?
    @State private var confirmLegacy = false
    @AppStorage(HostWhatsNew.seenKey) private var whatsNewSeen = ""
    /// `-debugHostWhatsNew YES` shows it at launch (UI checks).
    @State private var showWhatsNew = UserDefaults.standard.bool(forKey: "debugHostWhatsNew")
    @State private var pairedToast: String?
    @State private var toastHide: DispatchWorkItem?

    private var connected: Bool { host.sessionDevice != nil }
    private var usb: Bool { host.sessionLink.hasPrefix("USB") }
    private var allGranted: Bool { host.screenRecordingGranted && host.accessibilityGranted }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(page.title)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .padding(.top, 50)
                        content(page)
                    }
                    .padding(.horizontal, 28).padding(.bottom, 30)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.automatic)
                .mask {
                    // Content fades out under the top edge instead of being cut.
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 40)
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
                    }
                }
                .id(page)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
            }
        }
        .ignoresSafeArea(.container, edges: .top)   // the sidebar reaches up to the window buttons
        .background(ThemeBackground().ignoresSafeArea())
        .overlay { pairingOverlay }
        .overlay(alignment: .bottom) { toast }
        .tint(Brand.mint)
        .animation(Ultra.smooth, value: connected)
        .animation(Ultra.smooth, value: allGranted)
        .animation(Ultra.smooth, value: host.pairingCode)
        .animation(Ultra.smooth, value: host.mode)
        .animation(Ultra.smooth, value: pairedToast)
        .id(l10n.language)   // re-render every text when the language changes
        .task { await host.refreshSources() }
        .onChange(of: host.lastPaired) { _, name in if let name, onboardingDone { showPaired(name) } }
        .sheet(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            HostOnboarding(done: $onboardingDone).environmentObject(host)
        }
        .sheet(isPresented: $showWhatsNew) { HostWhatsNew() }
        .onAppear {
            // A fresh install gets the setup, which explains everything; updates get "What's new" once.
            if !onboardingDone { whatsNewSeen = HostWhatsNew.version }
            else if whatsNewSeen != HostWhatsNew.version { showWhatsNew = true }
        }
        .confirmationDialog(L("Alle Kopplungen aufheben?"), isPresented: $confirmUnpair) {
            Button(L("Aufheben"), role: .destructive) { host.unpairAll() }
        } message: {
            Text(L("Jedes iPad muss danach neu gekoppelt werden."))
        }
        .confirmationDialog(L("„%@“ entfernen?", confirmRemove?.name ?? ""),
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button(L("Entfernen"), role: .destructive) {
                if let d = confirmRemove { withAnimation(Ultra.smooth) { host.unpair(d) } }
                confirmRemove = nil
            }
        } message: {
            Text(L("Dieses iPad kann sich sofort nicht mehr verbinden und muss neu gekoppelt werden. Andere iPads bleiben gekoppelt."))
        }
        .confirmationDialog(L("Ältere Kopplungen aufheben?"), isPresented: $confirmLegacy) {
            Button(L("Aufheben"), role: .destructive) { withAnimation(Ultra.smooth) { host.retireLegacyPairings() } }
        } message: {
            Text(L("iPads, die sich seit dem Update noch nicht verbunden haben, müssen neu gekoppelt werden. iPads in der Liste bleiben gekoppelt."))
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                TafelMark().frame(width: 30, height: 30)
                Text("UniversePen").font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 6)
            VStack(spacing: 2) {
                ForEach(Array(HostPage.allCases.enumerated()), id: \.element) { i, p in
                    sidebarRow(p, index: i)
                }
            }
            Spacer(minLength: 0)
            sidebarStatus
        }
        .padding(.horizontal, 10)
        .padding(.top, 44)     // the window buttons sit above
        .padding(.bottom, 14)
        .frame(width: 214)
        .frame(maxHeight: .infinity, alignment: .top)
        .ultraGlass(Ultra.shape(20))
        .padding(10)
    }

    private func sidebarRow(_ p: HostPage, index: Int) -> some View {
        let on = p == page
        return Button {
            withAnimation(Ultra.smooth) { page = p }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: p.symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(on ? Brand.slateDeep : Color.white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background {
                        if on { Ultra.shape(8).fill(Ultra.accentFill) } else { Ultra.shape(8).fill(.white.opacity(0.09)) }
                    }
                Text(p.title).font(.system(size: 13, weight: on ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                if p == .overview && !allGranted {
                    Circle().fill(.orange).frame(width: 7, height: 7).transition(.scale)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background {
                if on { Ultra.shape(11).fill(.white.opacity(0.11)).matchedGeometryEffect(id: "page", in: sidebarSpace) }
            }
            .contentShape(Ultra.shape(11))
        }
        .buttonStyle(UltraPress(scale: 0.97))
        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var sidebarStatus: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(connected ? Brand.mint : host.listenerReady ? Color.white.opacity(0.35) : .orange)
                .frame(width: 7, height: 7)
                .shadow(color: connected ? Brand.mint : .clear, radius: 4)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(host.sessionDevice ?? L("Nicht verbunden")).font(.caption.weight(.semibold)).lineLimit(1)
                Text(connected ? localizedLink(host.sessionLink) : host.listenerStatus)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Pages

    @ViewBuilder private func content(_ p: HostPage) -> some View {
        switch p {
        case .overview: overview
        case .source: sourcePage
        case .pairing: pairingPage
        case .stream: streamPage
        case .general: generalPage
        case .developer: developerPage
        }
    }

    // MARK: Overview

    @ViewBuilder private var overview: some View {
        hero
        if !allGranted { permissions.transition(.move(edge: .top).combined(with: .opacity)) }
        if connected && !host.ipadProfiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                UltraHeader(L("Profil")).padding(.leading, 6)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(host.ipadProfiles, id: \.id) { p in
                            let on = p.id == host.ipadActiveProfile
                            Button { host.activateIPadProfile(p.id) } label: {
                                Label(p.name, systemImage: on ? "checkmark" : "person.crop.square")
                                    .font(.callout.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(on ? Brand.slateDeep : Color.white.opacity(0.9))
                                    .background { if on { Capsule().fill(Ultra.accentFill) } else { Capsule().fill(.white.opacity(0.08)) } }
                                    .overlay(Capsule().strokeBorder(.white.opacity(on ? 0.35 : 0.08), lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(UltraPress(scale: 0.95))
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 2).padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .animation(Ultra.snappy, value: host.ipadActiveProfile)
            }
            .transition(.opacity)
        }
        VStack(alignment: .leading, spacing: 8) {
            UltraHeader(L("Aktionen")).padding(.leading, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                UltraTile(L("Fenster aufs iPad"), symbol: "macwindow.badge.plus", enabled: connected && host.mode != .window, minHeight: 70) {
                    host.moveFrontWindowToIPad()
                }
                .help(L("Vorderstes Fenster aufs iPad"))
                UltraTile(L("Palette"), symbol: "square.on.square.dashed", on: host.paletteArea != nil, minHeight: 70) {
                    if host.paletteArea == nil { host.pickPalette() } else { host.removePalette() }
                }
                .help(host.paletteArea == nil ? L("Palette fürs iPad wählen …") : L("Palette entfernen"))
                UltraTile(L("Zeitraffer"), symbol: host.timelapseRunning ? "stop.circle.fill" : "record.circle",
                          on: host.timelapseRunning, enabled: connected || host.timelapseRunning, minHeight: 70) {
                    host.timelapseRunning ? host.stopTimelapse() : host.startTimelapse()
                }
                UltraTile(L("Stifttest"), symbol: "applepencil.and.scribble", minHeight: 70) { openPenTest() }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            UltraHeader(L("Quelle")).padding(.leading, 6)
            modeTiles(minHeight: 70)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                ConnectionOrb(connected: connected, usb: usb)
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 7) {
                    Text(host.sessionDevice ?? L("Warte auf iPad …"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .contentTransition(.opacity)
                    if connected {
                        HStack(spacing: 6) {
                            LinkChip(link: host.sessionLink)
                            if let b = host.ipadBattery { BatteryChip(level: b, charging: host.ipadCharging == true) }
                            if host.heatLevel > 0 {
                                UltraChip(text: host.heatGuard ? L("Gedrosselt") : L("Heiß"), symbol: "thermometer.high", color: .orange)
                                    .help(host.heatGuard ? L("Mac ist heiß – Stream gedrosselt (30 fps).") : L("Mac ist heiß."))
                            }
                        }
                        .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                    } else {
                        Text(L("UniversePen auf dem iPad öffnen – es verbindet sich automatisch."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if !host.extraTablets.isEmpty {
                        Label(L("+ als Tablett: %@", host.extraTablets.joined(separator: ", ")), systemImage: "rectangle.dashed")
                            .font(.callout).foregroundStyle(Brand.mintBright)
                    }
                }
                Spacer(minLength: 0)
            }
            if connected {
                StatTiles(live: host.live)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    Button { host.beginPairing() } label: {
                        Label(L("iPad koppeln …"), systemImage: "ipad.and.arrow.forward")
                    }
                    .buttonStyle(UltraProminent(compact: true))
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    Circle().fill(host.listenerReady ? Brand.mint : .orange).frame(width: 6, height: 6)
                    Text(host.listenerStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let e = host.lastError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Ultra.shape(26).fill(.white.opacity(0.06))
                Ultra.shape(26).fill(RadialGradient(colors: [Brand.mint.opacity(connected ? 0.28 : 0.1), .clear],
                                                    center: .topLeading, startRadius: 10, endRadius: 360))
            }
        }
        .overlay(Ultra.shape(26).strokeBorder(Ultra.edgeLight, lineWidth: 1))
    }

    private var permissions: some View {
        UltraSection(title: L("Berechtigungen")) {
            permissionRow(L("Bildschirmaufnahme"), symbol: "rectangle.dashed.badge.record", detail: L("Für die Übertragung des Bildes."),
                          granted: host.screenRecordingGranted, action: host.requestScreenRecording)
            permissionRow(L("Bedienungshilfen"), symbol: "accessibility", detail: L("Für Stift, Maus, Scrollen und Tastatur."),
                          granted: host.accessibilityGranted, action: host.requestAccessibility)
        }
    }

    private func permissionRow(_ title: String, symbol: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        SettingRow(symbol: symbol, title: title, detail: detail) {
            if granted {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Brand.mint)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(L("Erlauben …"), action: action).buttonStyle(UltraProminent(compact: true))
            }
        }
    }

    private func modeTiles(minHeight: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(CaptureMode.allCases) { m in
                let unavailable = m == .virtual && !HostController.secondScreenAvailable
                UltraTile(m.title, symbol: m.symbol, on: host.mode == m, enabled: !unavailable, minHeight: minHeight) {
                    host.mode = m
                }
                .help(unavailable ? L("Auf diesem macOS nicht verfügbar: die private Schnittstelle hat sich geändert.") : m.help)
            }
        }
    }

    // MARK: Source

    @ViewBuilder private var sourcePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeTiles(minHeight: 78)
            Text(host.mode.help).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .padding(.horizontal, 6)
            if host.mode == .virtual {
                UltraChip(text: L("Experimentell · private macOS-Schnittstelle"), symbol: "flask", color: .orange)
                    .padding(.horizontal, 4)
            }
            if !HostController.secondScreenAvailable {
                Label(L("„Zweiter Bildschirm“ ist auf diesem macOS nicht verfügbar – die private Schnittstelle hat sich geändert. Details stehen im Log (Konsole, Prozess „UniversePen Host“)."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 6)
            }
        }
        UltraSection(title: host.mode == .window ? L("Fenster") : host.mode == .virtual ? nil : L("Bildschirm")) {
            if host.mode == .window {
                SettingRow(symbol: "macwindow", title: L("Fenster")) {
                    Picker(L("Fenster"), selection: $host.selectedWindow) {
                        ForEach(host.windows) { Text($0.title).lineLimit(1).tag($0.id) }
                    }
                    .labelsHidden().frame(maxWidth: 280)
                }
            } else if host.mode != .virtual {
                SettingRow(symbol: "display", title: L("Bildschirm")) {
                    Picker(L("Bildschirm"), selection: $host.selectedDisplay) {
                        ForEach(host.displays) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden().frame(maxWidth: 280)
                }
            }
            if host.mode == .region {
                sliderRow(L("Größe"), value: $host.regionZoom, range: 0.2...1, symbol: "arrow.up.left.and.arrow.down.right")
                SettingRow(symbol: "plus.magnifyingglass", title: L("Lupe folgt dem Stift"),
                           detail: L("Der Ausschnitt wandert mit, wenn der Stift an den Rand des iPads kommt, und springt zum Zeiger, wenn du ihn am Mac woanders hinbewegst.")) {
                    UltraSwitch(label: L("Lupe folgt dem Stift"), isOn: $host.regionFollow)
                }
                sliderRow(L("Horizontal"), value: $host.regionAnchorX, range: 0...1, symbol: "arrow.left.and.right")
                sliderRow(L("Vertikal"), value: $host.regionAnchorY, range: 0...1, symbol: "arrow.up.and.down")
            }
            SettingRow(symbol: "arrow.clockwise", title: L("Quellen aktualisieren")) {
                Button(L("Aktualisieren")) { Task { await host.refreshSources() } }
                    .buttonStyle(UltraQuiet(compact: true))
            }
        }
        UltraSection(title: L("Palette")) {
            SettingRow(symbol: "square.on.square.dashed", title: host.paletteArea == nil ? L("Palette fürs iPad wählen …") : L("Palette neu wählen …"),
                       detail: L("Ein Bereich des Macs (z. B. Ebenen- oder Farbpalette) schwebt live als kleines Fenster auf dem iPad und lässt sich dort antippen.")) {
                HStack(spacing: 8) {
                    if host.paletteArea != nil {
                        Button(L("Entfernen")) { host.removePalette() }.buttonStyle(UltraQuiet(compact: true))
                    }
                    Button(L("Wählen")) { host.pickPalette() }.buttonStyle(UltraProminent(compact: true))
                }
            }
        }
        UltraSection {
            SettingRow(symbol: "laser.burst", title: L("Laserpointer-Farbe")) {
                HStack(spacing: 10) {
                    ForEach(LaserOverlay.Colour.allCases) { c in
                        let on = host.laserColour == c
                        let color = Color(nsColor: c.color)
                        Button { withAnimation(Ultra.snappy) { host.laserColour = c } } label: {
                            Circle().fill(color).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.white.opacity(on ? 0.95 : 0.15), lineWidth: on ? 2.5 : 1))
                                .shadow(color: on ? color.opacity(0.75) : .clear, radius: 6)
                                .scaleEffect(on ? 1.15 : 1)
                        }
                        .buttonStyle(.plain)
                        .help(c.title)
                        .accessibilityLabel(c.title)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
        UltraSection(title: L("Tastenkürzel")) {
            ForEach(Hotkeys.shortcuts, id: \.0) { action, _, keys in
                SettingRow(symbol: Self.symbol(action), title: Self.title(action)) { UltraKeyCaps(keys) }
            }
        }
    }

    private static func title(_ a: Hotkeys.Action) -> String {
        switch a {
        case .tabletMode: return L("Tablett-Modus")
        case .palette: return L("Palette fürs iPad wählen …")
        case .windowToIPad: return L("Vorderstes Fenster aufs iPad")
        }
    }

    private static func symbol(_ a: Hotkeys.Action) -> String {
        switch a {
        case .tabletMode: return "rectangle.dashed"
        case .palette: return "square.on.square.dashed"
        case .windowToIPad: return "macwindow.badge.plus"
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, symbol: String) -> some View {
        SettingRow(symbol: symbol, title: title) {
            Slider(value: value, in: range).frame(width: 240)
        }
    }

    // MARK: Pairing

    @ViewBuilder private var pairingPage: some View {
        UltraSection {
            SettingRow(symbol: "ipad.and.arrow.forward", title: L("iPad koppeln"),
                       detail: L("Öffne UniversePen auf dem iPad, tippe unter „Neu koppeln“ auf diesen Mac und gib den Code ein.")) {
                Button(L("Code anzeigen")) { host.beginPairing() }.buttonStyle(UltraProminent(compact: true))
            }
            if let p = host.lastPaired {
                SettingRow(symbol: "checkmark.seal.fill", title: L("Gekoppelt: %@", p))
            }
        }
        UltraSection(title: L("Verbindung")) {
            SettingRow(symbol: "dot.radiowaves.left.and.right", title: L("Peer-to-Peer-WLAN (ohne Router)"),
                       detail: L("Nur ohne gemeinsames WLAN und ohne Kabel einschalten – kostet Latenz.")) {
                UltraSwitch(label: L("Peer-to-Peer-WLAN (ohne Router)"), isOn: $host.peerToPeer)
            }
        }
        UltraSection(title: L("Gekoppelte iPads")) {
            if host.pairedIPads.isEmpty && !host.legacyPairings {
                SettingRow(symbol: "ipad", title: L("Noch kein iPad gekoppelt"))
            }
            ForEach(host.pairedIPads) { d in
                SettingRow(symbol: "ipad", title: d.name, detail: pairedDetail(d)) {
                    Button(L("Entfernen")) { confirmRemove = d }.buttonStyle(UltraQuiet(compact: true))
                }
            }
            if host.legacyPairings {
                SettingRow(symbol: "key.horizontal", title: L("Ältere Kopplungen"),
                           detail: L("iPads, die vor Version 0.8 gekoppelt wurden, nutzen noch einen gemeinsamen Schlüssel (%@). Sobald sich eins verbindet, bekommt es automatisch einen eigenen.", host.keyFingerprint)) {
                    Button(L("Aufheben")) { confirmLegacy = true }.buttonStyle(UltraQuiet(compact: true))
                }
            }
        }
        UltraSection(title: L("Sicherheit")) {
            SettingRow(symbol: "lock.shield", title: L("Jedes iPad hat seinen eigenen Schlüssel"),
                       detail: L("Ein entferntes iPad kann sich sofort nicht mehr verbinden; die anderen bleiben gekoppelt. Der Fingerabdruck steht auch auf dem iPad unter Einstellungen → Verbindung."))
            SettingRow(symbol: "link.badge.plus", title: L("Alle Kopplungen aufheben …"),
                       detail: L("Jedes iPad muss danach neu gekoppelt werden.")) {
                Button(L("Aufheben")) { confirmUnpair = true }.buttonStyle(UltraQuiet(compact: true))
            }
        }
    }

    private func pairedDetail(_ d: DeviceKeyStore.Device) -> String {
        let locale = Locale(identifier: L10n.shared.language.systemCode)
        let paired = d.pairedAt.formatted(.dateTime.day().month().year().locale(locale))
        let seen = d.lastSeen.map { $0.formatted(.relative(presentation: .named).locale(locale)) } ?? "–"
        return L("Gekoppelt am %@ · zuletzt verbunden %@", paired, seen) + "\n" + L("Fingerabdruck %@", host.fingerprint(of: d))
    }

    // MARK: Stream

    @ViewBuilder private var streamPage: some View {
        UltraSection {
            SettingRow(symbol: "cpu", title: L("Encoder"), detail: host.streamDescription.isEmpty ? "–" : host.streamDescription)
            SettingRow(symbol: "thermometer.medium", title: L("Hitzeschutz"),
                       detail: host.heatLevel == 0 ? L("Wird der Mac heiß, sinken Bildrate und Bitrate, bis er wieder kühl ist.")
                                : host.heatGuard ? L("Mac ist heiß – Stream gedrosselt (30 fps).") : L("Mac ist heiß."),
                       detailColor: host.heatLevel > 0 ? .orange : .secondary) {
                UltraSwitch(label: L("Hitzeschutz"), isOn: $host.heatGuard)
            }
        }
        UltraSection(title: L("Zeitraffer")) {
            TimelapseControls()
        }
        UltraSection(title: L("Stifttest")) {
            SettingRow(symbol: "applepencil.and.scribble", title: L("Stifttest öffnen …"),
                       detail: L("Zeigt, welche Druck-, Neigungs- und Rotationswerte eine Mac-App wirklich empfängt.")) {
                Button(L("Öffnen")) { openPenTest() }.buttonStyle(UltraQuiet(compact: true))
            }
        }
        if !host.clientDiagnostics.isEmpty, connected {
            UltraSection(title: L("Netzwerk-Diagnose")) {
                Text(Self.localizedDiagnostics(host.clientDiagnostics))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
    }

    /// The iPad sends its diagnostics with fixed German labels; show them in the Mac's language.
    static func localizedDiagnostics(_ s: String) -> String {
        var r = localizedLink(s)
        guard L10n.shared.language != .de else { return r }
        for (de, shown) in [("sichtbar:", L("sichtbar:")), ("Kabel-Kandidat:", L("Kabel-Kandidat:")),
                            ("Weg:", L("Weg:")), ("keiner", L("keiner"))] {
            r = r.replacingOccurrences(of: de, with: shown)
        }
        return r
    }

    private func openPenTest() {
        openWindow(id: "pentest")
        Task { try? await Task.sleep(nanoseconds: 500_000_000); await host.refreshSources(); host.restartStream() }
    }

    // MARK: General

    @ViewBuilder private var generalPage: some View {
        UltraSection {
            SettingRow(symbol: "power", title: L("Beim Anmelden öffnen")) {
                UltraSwitch(label: L("Beim Anmelden öffnen"), isOn: Binding(get: { host.openAtLogin }, set: { host.setOpenAtLogin($0) }))
            }
            SettingRow(symbol: "speaker.wave.2", title: L("Ton beim Verbinden und Trennen")) {
                UltraSwitch(label: L("Ton beim Verbinden und Trennen"), isOn: $host.connectSound)
            }
        }
        UltraSection(title: L("Farben")) {
            ThemeChoice().padding(.vertical, 6)
        }
        VStack(alignment: .leading, spacing: 8) {
            UltraHeader(L("Sprache")).padding(.leading, 6)
            LanguageChoice()
        }
        Button {
            onboardingDone = false
        } label: {
            Label(L("Einrichtung erneut starten"), systemImage: "sparkles")
        }
        .buttonStyle(UltraQuiet(compact: true))
    }

    // MARK: Developer

    @ViewBuilder private var developerPage: some View {
        UltraSection(title: L("Entwickler-API")) {
            SettingRow(symbol: "chevron.left.forwardslash.chevron.right", title: L("Entwickler-API"),
                       detail: L("Andere Programme auf diesem Mac lesen Stift-Eingaben und steuern UniversePen (nur lokal, 127.0.0.1:%d).", Int(DeveloperAPI.defaultPort))) {
                UltraSwitch(label: L("Entwickler-API"), isOn: $host.devAPIEnabled.animation(Ultra.smooth))
            }
            if host.devAPIEnabled {
                SettingRow(symbol: "link", title: L("%d Programme verbunden", host.devAPIClients),
                           detail: host.devAPIError, detailColor: .orange)
            }
            SettingRow(symbol: "book", title: L("Dokumentation (SDK, MIT-Lizenz)")) {
                Link(destination: URL(string: "https://github.com/bedsheetsosu/universepen/tree/main/SDK")!) {
                    Image(systemName: "arrow.up.right.square").foregroundStyle(Brand.mintBright)
                }
                .accessibilityLabel(L("Dokumentation (SDK, MIT-Lizenz)"))
            }
        }
        UltraSection(title: L("Plugins")) {
            SettingRow(symbol: "puzzlepiece.extension", title: L("Plugins"),
                       detail: L("Eigene Erweiterungen in JavaScript: Stift-Filter (z. B. Glättung), Gesten-Makros, Aktionen für das iPad, Einstellungen steuern. Wie OpenTabletDriver-Plugins, nur für UniversePen.")) {
                let on = host.plugins.entries.filter(\.enabled).count
                HStack(spacing: 8) {
                    if on > 0 { UltraChip(text: L("%d aktiv", on), symbol: "checkmark", color: Brand.mintBright) }
                    Button(L("Öffnen")) { openWindow(id: "plugins") }.buttonStyle(UltraQuiet(compact: true))
                }
            }
            SettingRow(symbol: "book", title: L("Plugin-Doku")) {
                Link(destination: URL(string: "https://github.com/bedsheetsosu/universepen/tree/main/SDK/plugins")!) {
                    Image(systemName: "arrow.up.right.square").foregroundStyle(Brand.mintBright)
                }
                .accessibilityLabel(L("Plugin-Doku"))
            }
        }
    }

    // MARK: Pairing code and toast

    @ViewBuilder private var pairingOverlay: some View {
        if let code = host.pairingCode, onboardingDone {
            ZStack {
                Rectangle().fill(.black.opacity(0.45)).ignoresSafeArea()
                    .onTapGesture {}
                    .transition(.opacity)
                PairingCodeView(code: code, seconds: host.pairingSecondsLeft) { host.endPairing() }
                    .padding(30)
                    .frame(width: 480)
                    .ultraGlass(Ultra.shape(Ultra.panelRadius))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 14)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder private var toast: some View {
        if let name = pairedToast {
            Label(L("%@ ist gekoppelt.", name), systemImage: "checkmark.seal.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 11)
                .ultraGlass(Capsule(), tint: Brand.mint.opacity(0.35))
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showPaired(_ name: String) {
        pairedToast = name
        toastHide?.cancel()
        let hide = DispatchWorkItem { pairedToast = nil }
        toastHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: hide)
    }
}

/// Start/stop the time-lapse, speed, running time and the last file.
private struct TimelapseControls: View {
    @EnvironmentObject var host: HostController
    @ObservedObject var theme = Theme.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if host.timelapseRunning {
                    Button {
                        withAnimation(Ultra.smooth) { host.stopTimelapse() }
                    } label: {
                        Label(L("Zeitraffer stoppen"), systemImage: "stop.fill")
                    }
                    .buttonStyle(UltraQuiet(compact: true))
                } else {
                    Button {
                        withAnimation(Ultra.smooth) { host.startTimelapse() }
                    } label: {
                        Label(L("Zeitraffer aufnehmen"), systemImage: "record.circle")
                    }
                    .buttonStyle(UltraProminent(compact: true))
                }
                Spacer()
                Text(L("Tempo")).font(.callout).foregroundStyle(.secondary).fixedSize()
                UltraSegmented([(10, "10×", nil), (30, "30×", nil), (60, "60×", nil), (120, "120×", nil)],
                               selection: $host.timelapseSpeed)
                    .frame(width: 240)
                    .disabled(host.timelapseRunning)
                    .opacity(host.timelapseRunning ? 0.5 : 1)
            }
            if host.timelapseRunning, let start = host.timelapseStarted {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                        .shadow(color: .red, radius: 4)
                    TimelineView(.periodic(from: start, by: 1)) { ctx in
                        let secs = Int(ctx.date.timeIntervalSince(start))
                        let movie = Double(host.timelapseFrames) / Double(TimelapseRecorder.outputFPS)
                        Text(L("Läuft seit %@ · %lld Bilder · ergibt %@ Video", Self.clock(secs), host.timelapseFrames, Self.clock(Int(movie.rounded()))))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } else if let file = host.timelapseLastFile {
                HStack {
                    Image(systemName: "film").foregroundStyle(Brand.mint)
                    Text(file.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    Button(L("Im Finder zeigen")) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                        .buttonStyle(.link).font(.caption)
                }
            }
            Text(L("Nimmt das übertragene Bild als Zeitraffer auf (Filme → UniversePen). Ruhephasen ohne Bildänderung werden automatisch übersprungen."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }

    static func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}
