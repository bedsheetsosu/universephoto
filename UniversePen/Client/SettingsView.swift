import SwiftUI
import UniformTypeIdentifiers
import TafelKit

struct SettingsView: View {
    @EnvironmentObject var model: ClientModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    /// The areas of the settings (sidebar entries).
    enum Page: String, CaseIterable, Identifiable {
        case general, look, connection, image, pencil, fingers, tablet, bar, radial, keyboard, profiles
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return L("Allgemein")
            case .look: return L("Aussehen")
            case .connection: return L("Verbindung")
            case .image: return L("Bild")
            case .pencil: return L("Stift")
            case .fingers: return L("Finger & Multi-Touch")
            case .tablet: return L("Tablett-Modus")
            case .bar: return L("Shortcuts")
            case .radial: return L("Radialmenü")
            case .keyboard: return L("Tastatur & Trackpad")
            case .profiles: return L("Profile")
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .look: return "paintpalette"
            case .connection: return "cable.connector"
            case .image: return "display"
            case .pencil: return "applepencil.and.scribble"
            case .fingers: return "hand.point.up.left"
            case .tablet: return "rectangle.dashed"
            case .bar: return "rectangle.grid.1x2"
            case .radial: return "circle.grid.cross"
            case .keyboard: return "keyboard"
            case .profiles: return "person.crop.square"
            }
        }

        /// What the page contains, in the current language (for the search).
        var keywords: [String] {
            switch self {
            case .general: return [L("Nur Monitor (keine Eingabe)"), L("Abdunkeln nach"), L("Pausen-Erinnerung"), L("Raster"),
                                   L("Latenz dauerhaft anzeigen"), L("Demo"), L("Einrichtung erneut starten")]
            case .look: return [L("Sprache"), L("Farben")]
            case .connection: return [L("Neu verbinden"), L("Trennen")]
            case .image: return [L("Bildrate"), L("Auflösung"), L("Volle Mac-Auflösung senden"), L("10-Bit-Farbe (keine Farbstufen)"), L("Spielmodus")]
            case .pencil: return [L("Druckkurve"), L("Doppeltippen"), L("Squeeze"), L("Squeeze halten"), L("Formerkennung"),
                                  L("Sofort-Tinte (Strich sofort auf dem iPad)"), L("Hover-Punkt unter der Stiftspitze"),
                                  L("Seil-Stabilisator"), L("Tempo-Druck"), L("Fester Druck"), L("Druck-Anzeige beim Zeichnen"),
                                  L("Undo/Redo-Knöpfe am Rand")]
            case .fingers: return [L("Zwei-Finger-Tipp"), L("Drei-Finger-Tipp"), L("Vier-Finger-Tipp"), L("Zoomen (Pinch)"),
                                   L("Undo-Wischen (zwei Finger halten, dann ziehen)")]
            case .tablet: return []
            case .bar: return []
            case .radial: return []
            case .keyboard: return [L("Textbausteine"), L("Trackpad / Maus steuert den Mac")]
            case .profiles: return []
            }
        }
    }

    @AppStorage("settingsPage") private var pageRaw = Page.general.rawValue
    @State private var query = ""
    @Namespace private var sidebarSpace

    private var page: Page { Page(rawValue: pageRaw) ?? .general }

    /// Pages matching the search, each with the first setting that matched (nil = its title did).
    private var results: [(page: Page, hit: String?)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Page.allCases.map { ($0, nil) } }
        func matches(_ t: String) -> Bool { t.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return Page.allCases.compactMap { p in
            if matches(p.title) { return (p, nil) }
            if let k = p.keywords.first(where: matches) { return (p, k) }
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 252)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1).ignoresSafeArea()
            NavigationStack {
                Form { pageContent(page).listRowBackground(Color.white.opacity(0.07)) }
                    .scrollContentBackground(.hidden)
                    .navigationTitle(page.title)
                    .toolbar { Button(L("Fertig")) { dismiss() }.fontWeight(.semibold) }
            }
            .id(page)   // a fresh stack per area (no half-open sub-page from another one)
        }
        .tint(Brand.mint)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Einstellungen"))
                .font(.title2.weight(.bold))
                .padding(.horizontal, 8).padding(.top, 22)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Suchen"), text: $query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Löschen"))
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.white.opacity(0.08), in: Capsule())
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(results, id: \.page) { r in sidebarRow(r.page, hit: r.hit) }
                    if results.isEmpty {
                        Text(L("Nichts gefunden")).font(.callout).foregroundStyle(.secondary).padding(.top, 24)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 12)
        .animation(Ultra.snappy, value: query)
    }

    private func sidebarRow(_ p: Page, hit: String?) -> some View {
        let on = p == page
        return Button {
            withAnimation(Ultra.snappy) { pageRaw = p.rawValue }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: p.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? Brand.slateDeep : Color.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background {
                        if on { Ultra.shape(9).fill(Ultra.accentFill) } else { Ultra.shape(9).fill(.white.opacity(0.09)) }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.title).font(.callout.weight(on ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
                    if let hit { Text(hit).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background {
                if on { Ultra.shape(14).fill(.white.opacity(0.11)).matchedGeometryEffect(id: "page", in: sidebarSpace) }
            }
            .contentShape(Ultra.shape(14))
        }
        .buttonStyle(UltraPress(scale: 0.97))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func pageContent(_ p: Page) -> some View {
        switch p {
        case .general:
            generalSection
            demoSection
        case .look:
            Section {
                LanguageChoice()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text(L("Sprache"))
            }
            Section {
                ThemeChoice()
            } header: {
                Text(L("Farben"))
            } footer: {
                Text(L("Akzentfarbe aus den Vorschlägen oder frei im Farbrad. „Fließender Hintergrund“ lässt die Farben langsam verlaufen und wandern (nur hinter Menüs und Einrichtung, nie über dem Mac-Bild)."))
            }
        case .connection: connectionSection
        case .image: imageSection
        case .pencil: pencilSection
        case .fingers: gestureSection
        case .tablet: tabletSection
        case .bar: shortcutSection
        case .radial: radialSection
        case .keyboard:
            keyboardSection
            snippetSection
        case .profiles: profilesSection
        }
    }

    private var generalSection: some View {
        Section {
            Toggle(L("Nur Monitor (keine Eingabe)"), isOn: $model.settings.viewOnly)
            Picker(L("Abdunkeln nach"), selection: $model.settings.dimAfterMinutes) {
                Text(L("Nie")).tag(0.0)
                Text("1 min").tag(1.0)
                Text("2 min").tag(2.0)
                Text("5 min").tag(5.0)
                Text("10 min").tag(10.0)
            }
            if model.settings.dimAfterMinutes > 0 {
                Toggle(L("Nicht abdunkeln, solange sich das Bild ändert"), isOn: $model.settings.dimOnlyWhenStill)
            }
            Stepper(L("Raster-Quadrate: %d", model.gridCells), value: $model.gridCells, in: 2...32)
            Toggle(L("Striche am Raster einrasten"), isOn: $model.gridSnap)
            VStack(alignment: .leading) {
                Text(L("Raster-Deckkraft: %d %%", Int(model.gridOpacity * 100)))
                Slider(value: $model.gridOpacity, in: 0.1...1)
            }
            Picker(L("Pausen-Erinnerung"), selection: $model.settings.breakReminderMinutes) {
                Text(L("Nie")).tag(0.0)
                Text("30 min").tag(30.0)
                Text("45 min").tag(45.0)
                Text("60 min").tag(60.0)
                Text("90 min").tag(90.0)
            }
            Toggle(L("Latenz dauerhaft anzeigen"), isOn: $model.showStatusOverlay)
            Toggle(L("Shortcut-Leiste rechts (Linkshänder)"), isOn: $model.settings.shortcutBarOnRight)
            Button(L("Einrichtung erneut starten")) {
                dismiss()
                model.onboardingDone = false
            }
        }
    }

    private var demoSection: some View {
        Section {
            Button {
                dismiss()
                model.demoMode = true
            } label: {
                Label(L("Demo-Modus starten"), systemImage: "sparkles")
            }
        } header: {
            Text(L("Demo"))
        } footer: {
            Text(L("Läuft nur auf dem iPad, ohne Mac: Zeichnen mit Druck und Neigung, Zeiger, Klicks und der Tablett-Modus mit Zielübung – zum Zeigen und Ausprobieren. Die Verbindung zum Mac bleibt dabei bestehen."))
        }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Mac", value: model.hostInfo?.hostName ?? "–")
            LabeledContent(L("Quelle"), value: model.hostInfo?.sourceDescription.isEmpty == false ? model.hostInfo!.sourceDescription : "–")
            if let t = model.timing {
                LabeledContent(L("Weg"), value: localizedLink(t.link))
                LabeledContent(L("Netz-RTT"), value: "\(Int(t.rttMs.rounded())) ms")
                if let a = t.frameAgeMs { LabeledContent(L("Bildalter bei Empfang"), value: "\(Int(a.rounded())) ms") }
                LabeledContent(L("Empfangen"), value: L("%d Bilder/s", Int(t.fps)))
            }
            if let id = model.hostInfo?.hostID, let p = model.paired.first(where: { $0.id == id }) {
                LabeledContent(L("Schlüssel-Fingerabdruck"), value: p.fingerprint)
                LabeledContent(L("Schlüssel"), value: p.keyID != nil ? L("Eigener Schlüssel dieses iPads")
                                                                      : L("Gemeinsamer Schlüssel (ältere Kopplung)"))
            }
            LabeledContent(L("Kabel-Kandidat"), value: model.cableInterface?.name ?? L("keiner"))
            LabeledContent(L("Sichtbare Schnittstellen"), value: model.visibleInterfaces.isEmpty ? "–" : model.visibleInterfaces)
            Toggle(L("Peer-to-Peer-WLAN (ohne Router)"), isOn: $model.peerToPeer)
            Button(L("Neu verbinden")) { model.retry() }
            Button(L("Trennen"), role: .destructive) { model.disconnect(); dismiss() }
        } header: {
            Text(L("Verbindung"))
        } footer: {
            Text(L("Mit USB-Kabel zum Mac verbindet UniversePen zuerst über das Kabel und sonst über WLAN. Peer-to-Peer-WLAN nur einschalten, wenn kein gemeinsames WLAN da ist – es erhöht die Latenz."))
        }
    }

    @State private var newSnippet = ""

    private var snippetSection: some View {
        Section {
            ForEach(Array(model.settings.snippets.enumerated()), id: \.offset) { _, t in Text(t) }
                .onDelete { model.settings.snippets.remove(atOffsets: $0) }
                .onMove { model.settings.snippets.move(fromOffsets: $0, toOffset: $1) }
            HStack {
                TextField(L("Neuer Textbaustein"), text: $newSnippet)
                Button(L("Hinzufügen")) {
                    let t = newSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { model.settings.snippets.append(t) }
                    newSnippet = ""
                }
                .disabled(newSnippet.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(L("Textbausteine"))
        } footer: {
            Text(L("Erscheinen im Menü oben rechts unter „Zwischenablage“; antippen tippt den Text am Mac (z. B. Ebenennamen, Signatur)."))
        }
    }

    private var keyboardSection: some View {
        Section {
            Toggle(L("Tasten ^ und < tauschen"), isOn: $model.settings.swapISOKeys)
            Toggle(L("Trackpad / Maus steuert den Mac"), isOn: $model.settings.trackpadAsMouse)
            Toggle(L("iPad-Zeiger ausblenden"), isOn: $model.settings.hideIPadPointer)
        } header: {
            Text(L("Tastatur & Trackpad"))
        } footer: {
            Text(L("Eine angeschlossene Tastatur (z. B. Logi Combo Touch) tippt direkt auf dem Mac – Taste für Taste, mit dem Tastaturlayout des Mac. Nicht übertragbar sind Kurzbefehle, die iPadOS selbst belegt (z. B. ⌘-Tab, ⌘-Leertaste, Globus-Taste). Trackpad: Zeigen, Klicken, Zwei-Finger-Klick = Rechtsklick, Zwei-Finger-Scrollen, Pinch = Zoom (Methode wie bei den Finger-Gesten). Die Bildschirmtastatur gibt es im Menü oben rechts unter „Zwischenablage“."))
        }
    }

    private var imageSection: some View {
        Section {
            Toggle(L("Ton vom Mac"), isOn: $model.quality.audio)
            Toggle(L("Bitrate automatisch anpassen"), isOn: $model.quality.adaptive)
            Picker("Codec", selection: $model.quality.codec) {
                Text("H.264").tag(VideoCodec.h264)
                Text("HEVC").tag(VideoCodec.hevc)
            }
            Picker(L("Bildrate"), selection: $model.quality.fps) {
                Text("60 fps").tag(60)
                Text("30 fps").tag(30)
            }
            Picker(L("Auflösung"), selection: $model.quality.resolutionScale) {
                Text(L("Nativ (100 %)")).tag(1.0)
                Text("75 %").tag(0.75)
                Text("50 %").tag(0.5)
            }
            Toggle(L("Volle Mac-Auflösung senden"), isOn: $model.quality.fullSource)
            // 10-bit needs HEVC; switching it on picks HEVC.
            Toggle(L("10-Bit-Farbe (keine Farbstufen)"), isOn: Binding(
                get: { model.quality.usesTenBit },
                set: { on in
                    model.quality.tenBit = on
                    if on { model.quality.codec = .hevc }
                }))
            VStack(alignment: .leading) {
                Text(L("Bitrate: %d Mbit/s", Int(model.quality.bitrateMbps)))
                Slider(value: $model.quality.bitrateMbps, in: 5...100, step: 5)
            }
            if let app = model.frontApp {
                Toggle(L("Spielmodus für %@", app.name), isOn: Binding(
                    get: { model.settings.gameApps[app.bundleID] != nil },
                    set: { _ in model.toggleGameMode() }))
                Toggle(L("Tablett-Modus automatisch für %@", app.name), isOn: Binding(
                    get: { model.autoTabletForFrontApp },
                    set: { _ in model.toggleAutoTablet() }))
            }
            ForEach(model.settings.tabletApps.sorted { $0.value < $1.value }.filter { $0.key != model.frontApp?.bundleID }, id: \.key) { id, name in
                LabeledContent(L("Tablett-Modus automatisch"), value: name)
                    .swipeActions { Button(L("Löschen"), role: .destructive) { model.settings.tabletApps[id] = nil } }
            }
            let otherGames = model.settings.gameApps.sorted { $0.value < $1.value }.filter { $0.key != model.frontApp?.bundleID }
            ForEach(otherGames, id: \.key) { _, name in
                LabeledContent(L("Spielmodus"), value: name)
            }
            .onDelete { idx in
                for i in idx where otherGames.indices.contains(i) { model.settings.gameApps[otherGames[i].key] = nil }
            }
        } header: {
            Text(L("Bild"))
        } footer: {
            Text(L("Höhere Bitrate = schärfer, braucht aber stabiles WLAN. Bei Rucklern Bitrate senken oder 30 fps wählen.") + " " +
                 L("Spielmodus (z. B. für osu!): Solange die App am Mac vorne ist, gelten 60 fps, volle Auflösung, mindestens 60 Mbit/s, keine automatische Bitrate und keine Glättung. Mehr als 60 Hz kann das iPad-Display nicht zeigen.") + " " +
                 L("„Volle Mac-Auflösung“: Der Mac schickt alle Pixel unverkleinert (z. B. beim zweiten Bildschirm mit mehr Platz), das iPad verkleinert beim Anzeigen. Kann schärfer sein, braucht aber mehr Bitrate."))
        }
    }

    /// "" = standard Pencil settings, otherwise the bundle ID of a Mac app with its own profile.
    @State private var penTarget = ""

    private var penApps: [(id: String, name: String)] {
        var ids = Set(model.settings.appPenProfiles.keys)
        if let f = model.frontApp { ids.insert(f.bundleID) }
        return ids.map { id in (id, model.settings.appNames[id] ?? (model.frontApp?.bundleID == id ? model.frontApp!.name : id)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var targetHasOwnProfile: Bool { !penTarget.isEmpty && model.settings.appPenProfiles[penTarget] != nil }

    private var pen: Binding<PenProfile> {
        Binding(get: {
            penTarget.isEmpty ? model.settings.penProfile : (model.settings.appPenProfiles[penTarget] ?? model.settings.penProfile)
        }, set: { v in
            if penTarget.isEmpty { model.settings.penProfile = v } else { model.settings.appPenProfiles[penTarget] = v }
        })
    }

    private var pencilSection: some View {
        Section {
            Picker(L("Einstellungen für"), selection: $penTarget) {
                Text(L("Standard (alle Apps)")).tag("")
                ForEach(penApps, id: \.id) { app in
                    Text(model.settings.appPenProfiles[app.id] == nil ? app.name : "\(app.name) ★").tag(app.id)
                }
            }
            if !penTarget.isEmpty && !targetHasOwnProfile {
                Button(L("Eigenes Stift-Profil für diese App anlegen")) {
                    model.settings.appPenProfiles[penTarget] = model.settings.penProfile
                    model.settings.appNames[penTarget] = penApps.first { $0.id == penTarget }?.name
                }
            } else {
                NavigationLink {
                    Form {
                        Section {
                            PressureCurveEditor(curve: pen.pressure)
                                .listRowBackground(Color.clear)
                            HStack {
                                ForEach(PressureCurve.Preset.allCases, id: \.self) { p in
                                    Button(p.title) { withAnimation(Brand.spring) { pen.wrappedValue.pressure.apply(p) } }
                                        .buttonStyle(.bordered)
                                        .tint(pen.wrappedValue.pressure.points == p.points ? Brand.mint : .secondary)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        } footer: {
                            Text(L("Punkte mit dem Finger ziehen. Unten mit dem Pencil drücken, um zu sehen, wo dein Druck auf der Kurve landet."))
                        }
                    }
                    .themedForm()
                    .navigationTitle(L("Druckkurve"))
                } label: {
                    LabeledContent(L("Druckkurve"), value: pen.wrappedValue.pressure.points.isEmpty ? L("Voreinstellung") : L("Eigene Kurve"))
                }
                VStack(alignment: .leading) {
                    Text(L("Strich glätten: %d %%", Int(pen.wrappedValue.positionSmoothing * 100)))
                    Slider(value: pen.positionSmoothing, in: 0...1)
                }
                VStack(alignment: .leading) {
                    Text(L("Druck glätten: %d %%", Int(pen.wrappedValue.pressureSmoothing * 100)))
                    Slider(value: pen.pressureSmoothing, in: 0...1)
                }
                VStack(alignment: .leading) {
                    Text(L("Mindestdruck: %.2f", pen.wrappedValue.pressure.minimum))
                    Slider(value: pen.pressure.minimum, in: 0...0.2)
                }
                ActionPicker(title: L("Doppeltippen"), action: pen.doubleTap)
                ActionPicker(title: L("Squeeze"), action: pen.squeeze)
                Picker(L("Squeeze halten"), selection: $model.settings.squeezeHoldKey) {
                    Text(L("Aus")).tag(HoldKey?.none)
                    ForEach(HoldKey.allCases, id: \.self) { k in
                        Text(k == .space ? L("Leertaste") : k.symbol).tag(HoldKey?.some(k))
                    }
                }
                if targetHasOwnProfile {
                    Button(L("Eigenes Stift-Profil löschen"), role: .destructive) {
                        model.settings.appPenProfiles[penTarget] = nil
                        if model.settings.appShortcutBars[penTarget] == nil { model.settings.appNames[penTarget] = nil }
                        penTarget = ""
                    }
                }
            }
            Toggle(L("Neigung X umkehren"), isOn: $model.settings.tilt.invertX)
            Toggle(L("Neigung Y umkehren"), isOn: $model.settings.tilt.invertY)
            Toggle(L("Doppeltippen zum Klicken (Pencil ohne Hover)"), isOn: $model.settings.doubleTapToClick)
            Toggle(L("Sofort-Tinte (Strich sofort auf dem iPad)"), isOn: $model.settings.instantInk)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.settings.ropeLength > 0 ? L("Seil-Stabilisator: %d pt", Int(model.settings.ropeLength)) : L("Seil-Stabilisator: aus"))
                Slider(value: $model.settings.ropeLength, in: 0...60, step: 2)
                Text(L("Der Strich hängt an einem unsichtbaren Seil hinter dem Pencil – Zittern innerhalb der Seillänge kommt nicht an. Für ruhige Linien und Schrift."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.settings.speedPressure > 0 ? L("Tempo-Druck: %d %%", Int(model.settings.speedPressure * 100)) : L("Tempo-Druck: aus"))
                Slider(value: $model.settings.speedPressure, in: 0...1, step: 0.05)
                Text(L("Schnelle Striche werden dünner, langsame bleiben satt – wie eine Tuschefeder."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle(L("Fester Druck (gleichmäßige Linie)"), isOn: Binding(
                    get: { model.settings.constantPressure > 0 },
                    set: { model.settings.constantPressure = $0 ? 0.6 : 0 }))
                if model.settings.constantPressure > 0 {
                    Text(L("Druck: %d %%", Int(model.settings.constantPressure * 100)))
                    Slider(value: $model.settings.constantPressure, in: 0.05...1)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle(L("Formerkennung"), isOn: $model.settings.shapeRecognition)
                Text(L("Am Strichende den Stift kurz still halten: Linie, Kreis, Ellipse, Dreieck oder Rechteck wird sauber neu gezeichnet (der Strich wird dafür am Mac rückgängig gemacht)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(L("Druck-Anzeige beim Zeichnen"), isOn: $model.settings.pressureMeter)
            Toggle(L("Undo/Redo-Knöpfe am Rand"), isOn: $model.settings.undoButtons)
            Toggle(L("Hover-Punkt unter der Stiftspitze"), isOn: $model.settings.hoverDot)
            if model.settings.hoverDot {
                Toggle(L("Neigung am Hover-Punkt zeigen"), isOn: $model.settings.hoverTilt)
                Stepper(L("Hover-Punkt: %d pt", Int(model.settings.hoverDotSize)), value: $model.settings.hoverDotSize, in: 4...40, step: 2)
            }
            Toggle(L("Eigene Farbe für Sofort-Tinte"), isOn: Binding(
                get: { !model.settings.inkColor.isEmpty },
                set: { model.settings.inkColor = $0 ? "FF3B30" : "" }))
            if !model.settings.inkColor.isEmpty {
                ColorPicker(L("Tinten-Farbe"), selection: Binding(
                    get: { Theme.color(model.settings.inkColor) },
                    set: { if let h = Theme.hex(of: $0) { model.settings.inkColor = h } }), supportsOpacity: false)
            }
            Toggle(L("Schweben (Hover) senden"), isOn: $model.settings.sendHover)
            Toggle(L("Barrel Roll als Rotation senden"), isOn: $model.settings.sendRoll)
        } header: {
            Text(L("Stift"))
        } footer: {
            Text(L("Druckkurve, Glättung, Doppeltippen und Squeeze können pro Mac-App eigene Werte haben (★) und wechseln automatisch mit der App, die am Mac vorne ist. Ob Neigung und Rotation in einer Mac-App ankommen, hängt von der App ab.") + " " +
                 L("Pencil ohne Hover (Apple Pencil 1, USB-C oder iPads ohne Schweben): Mit „Doppeltippen zum Klicken“ bewegt eine Berührung nur den Zeiger, erst nochmal sofort an derselben Stelle aufsetzen klickt bzw. zeichnet. Alternativen: „Klick ab Druck“ (leicht = Zeiger, fest = Klick) oder Finger-Modus „Zeiger“ (mit dem Finger zielen, mit dem Stift zeichnen)."))
        }
    }

    @State private var newProfileName = ""
    @State private var askProfileName = false
    @State private var renaming: SettingsProfile?
    @State private var renameText = ""
    @State private var importing = false

    private var profilesSection: some View {
        Section {
            ForEach(model.profiles) { p in
                Button {
                    if model.activeProfileID != p.id { withAnimation(Brand.spring) { model.switchProfile(p) } }
                } label: {
                    HStack {
                        Image(systemName: model.activeProfileID == p.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.activeProfileID == p.id ? Brand.mint : .secondary)
                            .accessibilityHidden(true)
                        Text(p.name).foregroundStyle(.primary)
                        Spacer()
                        if p.settings.tabletMode { Text(L("Tablett-Modus")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .accessibilityAddTraits(model.activeProfileID == p.id ? .isSelected : [])
                .contextMenu {
                    Button(L("Umbenennen")) { renameText = p.name; renaming = p }
                    Button(L("Duplizieren")) { model.duplicateProfile(p) }
                    ShareLink(item: ProfileExport(profile: p), preview: SharePreview(p.name)) {
                        Label(L("Exportieren …"), systemImage: "square.and.arrow.up")
                    }
                    Button(L("Löschen"), role: .destructive) { model.deleteProfile(p) }
                }
            }
            .onDelete { idx in for i in idx { model.deleteProfile(model.profiles[i]) } }
            Button {
                newProfileName = ""
                askProfileName = true
            } label: {
                Label(L("Neues Profil aus aktuellen Einstellungen"), systemImage: "plus.circle")
            }
            Button {
                importing = true
            } label: {
                Label(L("Profil importieren …"), systemImage: "square.and.arrow.down")
            }
            if model.profiles.count > 1 {
                ShareLink(item: ProfileExport(profiles: model.profiles), preview: SharePreview(L("Alle Profile"))) {
                    Label(L("Alle Profile exportieren …"), systemImage: "square.and.arrow.up.on.square")
                }
            }
        } header: {
            Text(L("Profile"))
        } footer: {
            Text(model.profiles.isEmpty
                 ? L("Profile sind komplette Einstellungs-Sätze (z. B. „Zeichnen“ und „osu!“). Lege eins an, dann landen Änderungen automatisch im aktiven Profil.")
                 : L("Änderungen landen automatisch im aktiven Profil. Gedrückt halten: umbenennen, duplizieren, löschen. Wechseln geht auch im Menü oben rechts unter „Mehr“."))
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let n = (try? Data(contentsOf: url)).map { model.importProfiles(from: $0) } ?? 0
            model.show(Toast(text: n > 0 ? L("%d Profil(e) importiert", n) : L("Keine UniversePen-Profile in dieser Datei"), seconds: 2))
        }
        .alert(L("Neues Profil"), isPresented: $askProfileName) {
            TextField(L("Name"), text: $newProfileName)
            Button(L("Anlegen")) { withAnimation(Brand.spring) { model.createProfile(named: newProfileName) } }
            Button(L("Abbrechen"), role: .cancel) {}
        }
        .alert(L("Umbenennen"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Name"), text: $renameText)
            Button(L("Speichern")) { if let p = renaming { model.renameProfile(p, to: renameText) }; renaming = nil }
            Button(L("Abbrechen"), role: .cancel) { renaming = nil }
        }
    }

    private var tabletSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text(model.settings.tipThreshold == 0 ? L("Klick ab Druck: sofort") : L("Klick ab Druck: %d %%", Int(model.settings.tipThreshold * 100)))
                Slider(value: $model.settings.tipThreshold, in: 0...0.6, step: 0.01)
            }
            Toggle(L("Tasten-Feld (wie ExpressKeys)"), isOn: $model.settings.tabletKeys.enabled)
            if model.settings.tabletKeys.enabled {
                Picker(L("Seite"), selection: $model.settings.tabletKeys.side) {
                    Text(L("Links")).tag(TabletKeys.Side.left)
                    Text(L("Rechts")).tag(TabletKeys.Side.right)
                    Text(L("Oben")).tag(TabletKeys.Side.top)
                    Text(L("Unten")).tag(TabletKeys.Side.bottom)
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    Text(L("Tastengröße: %d pt", Int(model.settings.tabletKeys.size)))
                    Slider(value: $model.settings.tabletKeys.size, in: 70...200, step: 5)
                }
                VStack(alignment: .leading) {
                    Text(model.settings.tabletKeys.side.horizontal ? L("Position: links ↔ rechts") : L("Position: oben ↔ unten"))
                    Slider(value: $model.settings.tabletKeys.vertical, in: 0...1)
                }
                ForEach($model.settings.tabletKeys.keys) { $k in
                    HStack {
                        TextField(L("Beschriftung"), text: $k.title).frame(maxWidth: 140)
                        Spacer()
                        Text(L("Taste")).foregroundStyle(.secondary)
                        TextField("z", text: Binding(get: { k.key }, set: { v in
                            let t = v.trimmingCharacters(in: .whitespaces).lowercased()
                            k.key = Shortcut.specialKeys[t] != nil ? t : String(t.suffix(1))
                        }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    }
                }
                .onDelete { model.settings.tabletKeys.keys.remove(atOffsets: $0) }
                .onMove { model.settings.tabletKeys.keys.move(fromOffsets: $0, toOffset: $1) }
                if model.settings.tabletKeys.keys.count < 6 {
                    Button(L("Taste hinzufügen")) {
                        model.settings.tabletKeys.keys.append(TabletKey(title: "C", key: "c"))
                    }
                }
            }
        } header: {
            Text(L("Tablett-Modus"))
        } footer: {
            Text(L("Klick ab Druck: leichte Berührungen bleiben Schweben, erst ab diesem Druck wird geklickt (gilt immer, nicht nur im Tablett-Modus). Tasten-Feld: große Touch-Tasten am Rand im Tablett-Modus – Finger drauf hält die Taste am Mac (z. B. Z/X für osu!). Taste: ein Zeichen oder space, return, tab, esc, delete, left, right, up, down. Im Bereich-Editor kannst du jede Taste frei verschieben und den Bereich drehen."))
        }
    }

    private var radialSection: some View {
        Section {
            ForEach($model.settings.radialMenu) { $b in
                NavigationLink {
                    ShortcutButtonEditor(button: $b)
                } label: {
                    LabeledContent(b.title, value: b.actionDisplay)
                }
            }
            .onDelete { idx in
                guard model.settings.radialMenu.count - idx.count >= 2 else { return }
                model.settings.radialMenu.remove(atOffsets: idx)
            }
            .onMove { model.settings.radialMenu.move(fromOffsets: $0, toOffset: $1) }
            if model.settings.radialMenu.count < InputSettings.maxRadialItems {
                Button(L("Aktion hinzufügen")) {
                    model.settings.radialMenu.append(ShortcutButton(title: L("Neu"), shortcut: Shortcut("a")))
                }
            }
            Button(L("Auf Standard zurücksetzen")) { model.settings.radialMenu = InputSettings.defaultRadialMenu }
        } header: {
            Text(L("Radialmenü"))
        } footer: {
            Text(L("Squeeze oder Doppeltippen auf „Radialmenü“ stellen. Dann erscheint an der Stiftspitze ein Ring: mit dem Pencil darüber schweben und nochmal drücken, oder antippen. Mitte oder daneben tippen schließt ihn. 2 bis 8 Aktionen, oben beginnend im Uhrzeigersinn."))
        }
    }

    private var gestureSection: some View {
        Section {
            Picker(L("Ein Finger"), selection: $model.settings.fingerMode) {
                ForEach(FingerMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if model.settings.fingerMode == .pen {
                VStack(alignment: .leading) {
                    Text(L("Druck beim Finger: %d %%", Int(model.settings.fingerPressure * 100)))
                    Slider(value: $model.settings.fingerPressure, in: 0.1...1)
                }
            }
            if model.settings.fingerMode != .off {
                Toggle(L("Halten = Rechtsklick"), isOn: $model.settings.longPressRightClick)
                VStack(alignment: .leading) {
                    Text(L("Handballen-Erkennung: ab %d pt Auflagefläche", Int(model.settings.palmRadius)))
                    Slider(value: $model.settings.palmRadius, in: 15...60, step: 1)
                }
            }
            Toggle(L("Undo-Wischen (zwei Finger halten, dann ziehen)"), isOn: $model.settings.undoScrub)
            if model.settings.undoScrub {
                VStack(alignment: .leading) {
                    Text(L("Weg pro Schritt: %d pt", Int(model.settings.undoScrubStep)))
                    Slider(value: $model.settings.undoScrubStep, in: 15...100, step: 5)
                }
            }
            Toggle(L("Zwei Finger verschieben (Scrollen)"), isOn: $model.settings.panEnabled)
            Toggle(L("Verschieben umkehren"), isOn: $model.settings.invertPan)
            Picker(L("Zoomen (Pinch)"), selection: $model.settings.zoomMethod) {
                ForEach(ZoomMethod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if model.settings.zoomMethod != .keyboardSteps && model.settings.zoomMethod != .off {
                VStack(alignment: .leading) {
                    Text(L("Zoom-Empfindlichkeit"))
                    Slider(value: $model.settings.zoomSensitivity, in: 0.05...1)
                }
            }
            ActionPicker(title: L("Drehen links"), action: $model.settings.rotateLeft)
            ActionPicker(title: L("Drehen rechts"), action: $model.settings.rotateRight)
            Stepper(L("Drehschritt: %d°", Int(model.settings.rotateStepDegrees)), value: $model.settings.rotateStepDegrees, in: 5...90, step: 5)
            ActionPicker(title: L("Zwei-Finger-Tipp"), action: $model.settings.twoFingerTap)
            ActionPicker(title: L("Drei-Finger-Tipp"), action: $model.settings.threeFingerTap)
            ActionPicker(title: L("Vier-Finger-Tipp"), action: $model.settings.fourFingerTap)
            ActionPicker(title: L("Drei Finger nach links"), action: $model.settings.threeFingerSwipeLeft)
            ActionPicker(title: L("Drei Finger nach rechts"), action: $model.settings.threeFingerSwipeRight)
            ActionPicker(title: L("Drei Finger nach oben"), action: $model.settings.threeFingerSwipeUp)
            ActionPicker(title: L("Drei Finger nach unten"), action: $model.settings.threeFingerSwipeDown)
        } header: {
            Text(L("Finger & Multi-Touch"))
        } footer: {
            Text(L("Wie bei einem Stift-Display: Ein Finger tippt (Klick), zieht (Klicken und Ziehen – zeichnet ohne Druck) und hält (Rechtsklick). Liegt der Stift in der Nähe oder wurde gerade benutzt, und bei großer Auflagefläche (Handballen), lösen Finger nichts aus. Vier-Finger-Gesten fängt iPadOS ab, wenn in den iPad-Einstellungen Multitasking-Gesten aktiv sind."))
        }
    }

    /// "" = standard bar, otherwise the bundle ID of a Mac app with its own bar.
    @State private var barTarget = ""

    private var barApps: [(id: String, name: String)] {
        var ids = Set(model.settings.appShortcutBars.keys)
        if let f = model.frontApp { ids.insert(f.bundleID) }
        return ids.map { id in (id, model.settings.appNames[id] ?? (model.frontApp?.bundleID == id ? model.frontApp!.name : id)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var targetHasOwnBar: Bool { !barTarget.isEmpty && model.settings.appShortcutBars[barTarget] != nil }

    private var bar: Binding<[ShortcutButton]> {
        Binding(get: {
            barTarget.isEmpty ? model.settings.shortcutBar : (model.settings.appShortcutBars[barTarget] ?? model.settings.shortcutBar)
        }, set: { v in
            if barTarget.isEmpty { model.settings.shortcutBar = v } else { model.settings.appShortcutBars[barTarget] = v }
        })
    }

    private var shortcutSection: some View {
        Section {
            Toggle(L("Shortcut-Leiste anzeigen"), isOn: $model.settings.showShortcutBar)
            Picker(L("Leiste für"), selection: $barTarget) {
                Text(L("Standard (alle Apps)")).tag("")
                ForEach(barApps, id: \.id) { app in
                    Text(model.settings.appShortcutBars[app.id] == nil ? app.name : "\(app.name) ★").tag(app.id)
                }
            }
            if !barTarget.isEmpty && !targetHasOwnBar {
                Button(L("Eigene Leiste für diese App anlegen")) {
                    model.settings.appShortcutBars[barTarget] = model.settings.shortcutBar
                    model.settings.appNames[barTarget] = barApps.first { $0.id == barTarget }?.name
                }
            } else {
                ForEach(bar) { $b in
                    NavigationLink {
                        ShortcutButtonEditor(button: $b)
                    } label: {
                        LabeledContent(b.title, value: b.actionDisplay)
                    }
                }
                .onDelete { bar.wrappedValue.remove(atOffsets: $0) }
                .onMove { bar.wrappedValue.move(fromOffsets: $0, toOffset: $1) }
                Button(L("Taste hinzufügen")) {
                    bar.wrappedValue.append(ShortcutButton(title: L("Neu"), shortcut: Shortcut("a")))
                }
                if targetHasOwnBar {
                    Button(L("Eigene Leiste löschen"), role: .destructive) {
                        model.settings.appShortcutBars[barTarget] = nil
                        model.settings.appNames[barTarget] = nil
                        barTarget = ""
                    }
                }
            }
        } header: {
            Text(L("Shortcuts"))
        } footer: {
            Text(L("Die Leiste wechselt automatisch mit der App, die am Mac vorne ist (★ = eigene Leiste). Halte-Tasten (⇧ ⌥ ⌘ ⌃ Leertaste) bleiben gedrückt, solange der Finger darauf liegt – zum Beispiel ⇧ beim Zeichnen gerader Linien. Tasten werden auf dem Mac anhand des aktiven Tastaturlayouts aufgelöst."))
        }
    }
}

/// Picker for a configurable action with common Affinity presets + custom shortcut.
struct ActionPicker: View {
    let title: String
    @Binding var action: PencilAction
    @EnvironmentObject var model: ClientModel

    private enum Preset: String, CaseIterable, Identifiable {
        case none, radialMenu, undo, redo, eraser, brush, hand, desktopLeft, desktopRight, missionControl, appWindows, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return L("Keine")
            case .radialMenu: return L("Radialmenü")
            case .undo: return L("Widerrufen ⌘Z")
            case .redo: return L("Wiederholen ⇧⌘Z")
            case .eraser: return L("Radierer (E)")
            case .brush: return L("Pinsel (B)")
            case .hand: return L("Hand (H)")
            case .desktopLeft: return L("Schreibtisch links ⌃←")
            case .desktopRight: return L("Schreibtisch rechts ⌃→")
            case .missionControl: return L("Mission Control ⌃↑")
            case .appWindows: return L("App-Fenster ⌃↓")
            case .custom: return L("Eigener Shortcut")
            }
        }
        var action: PencilAction {
            switch self {
            case .none: return .none
            case .radialMenu: return .radialMenu
            case .undo: return .undo
            case .redo: return .redo
            case .eraser: return .eraser
            case .brush: return .brush
            case .hand: return .hand
            case .desktopLeft: return .desktopLeft
            case .desktopRight: return .desktopRight
            case .missionControl: return .missionControl
            case .appWindows: return .appWindows
            case .custom: return .shortcut(Shortcut("a"))
            }
        }
    }

    private var preset: Binding<Preset> {
        Binding(get: {
            Preset.allCases.first { $0 != .custom && $0.action == action } ?? .custom
        }, set: { p in
            if p != .custom || action.shortcut == nil || Preset.allCases.contains(where: { $0 != .custom && $0.action == action }) {
                action = p.action
            }
        })
    }

    /// Picker value: a preset name or "plugin:<id>".
    private var choice: Binding<String> {
        Binding(get: {
            if case .plugin(let id) = action { return "plugin:" + id }
            if case .tool(let t) = action { return "tool:" + t.rawValue }
            return preset.wrappedValue.rawValue
        }, set: { v in
            if v.hasPrefix("plugin:") { action = .plugin(String(v.dropFirst(7))) }
            else if v.hasPrefix("tool:"), let t = IPadTool(rawValue: String(v.dropFirst(5))) { action = .tool(t) }
            else if let p = Preset(rawValue: v) { preset.wrappedValue = p }
        })
    }

    var body: some View {
        Picker(title, selection: choice) {
            ForEach(Preset.allCases) { Text($0.label).tag($0.rawValue) }
            Divider()
            ForEach(IPadTool.allCases, id: \.self) { t in Text("✎ " + t.title).tag("tool:" + t.rawValue) }
            if !model.pluginActions.isEmpty || isPlugin {
                Divider()
                ForEach(model.pluginActions) { a in Text("⚙︎ " + a.title).tag("plugin:" + a.id) }
                if isPlugin, case .plugin(let id) = action, !model.pluginActions.contains(where: { $0.id == id }) {
                    Text("⚙︎ " + id + " " + L("(Plugin aus)")).tag("plugin:" + id)
                }
            }
        }
        if !isPlugin, !isTool, preset.wrappedValue == .custom, let s = action.shortcut {
            ShortcutEditor(shortcut: Binding(get: { s }, set: { action = .shortcut($0) }))
                .padding(.leading, 16)
        }
    }
}

extension ActionPicker {
    var isPlugin: Bool { if case .plugin = action { return true } else { return false } }
    var isTool: Bool { if case .tool = action { return true } else { return false } }
}

struct ShortcutEditor: View {
    @Binding var shortcut: Shortcut

    private static let specials = ["esc", "delete", "tab", "space", "return", "left", "right", "up", "down"]

    var body: some View {
        HStack {
            Text(L("Taste"))
            Spacer()
            TextField(L("z. B. z, +, [, esc"), text: Binding(
                get: { shortcut.key },
                set: { v in
                    let t = v.trimmingCharacters(in: .whitespaces).lowercased()
                    if Self.specials.contains(t) { shortcut.key = t } else if let last = t.last { shortcut.key = String(last) }
                }))
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(maxWidth: 160)
        }
        HStack(spacing: 8) {
            modifierToggle("⌘", .command)
            modifierToggle("⇧", .shift)
            modifierToggle("⌥", .option)
            modifierToggle("⌃", .control)
            Spacer()
            Text(shortcut.display).font(.body.monospaced()).foregroundStyle(.secondary)
        }
    }

    private func modifierToggle(_ label: String, _ m: ModifierSet) -> some View {
        Toggle(label, isOn: Binding(
            get: { shortcut.modifiers.contains(m) },
            set: { on in if on { shortcut.modifiers.insert(m) } else { shortcut.modifiers.remove(m) } }))
        .toggleStyle(.button)
    }
}

/// Edits one bar button: title, and either a shortcut or a key to hold.
struct ShortcutButtonEditor: View {
    @Binding var button: ShortcutButton
    @EnvironmentObject var model: ClientModel

    var body: some View {
        Form {
            TextField(L("Titel"), text: $button.title)
            Picker(L("Art"), selection: Binding(get: { button.tool != nil ? 3 : button.pluginAction != nil ? 2 : button.hold == nil ? 0 : 1 },
                                                set: { v in
                                                    button.hold = v == 1 ? (button.hold ?? .shift) : nil
                                                    button.pluginAction = v == 2 ? (button.pluginAction ?? model.pluginActions.first?.id ?? "") : nil
                                                    button.tool = v == 3 ? (button.tool ?? .ruler) : nil
                                                })) {
                Text(L("Shortcut senden")).tag(0)
                Text(L("Taste halten")).tag(1)
                Text(L("Plugin-Aktion")).tag(2)
                Text(L("iPad-Werkzeug")).tag(3)
            }
            .pickerStyle(.segmented)
            if button.tool != nil {
                Picker(L("Werkzeug"), selection: Binding(get: { button.tool ?? .ruler }, set: { t in
                    // Keep a custom title; replace the default one.
                    if button.title == L("Neu") || IPadTool.allCases.contains(where: { $0.shortTitle == button.title }) { button.title = t.shortTitle }
                    button.tool = t
                })) {
                    ForEach(IPadTool.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } else if button.pluginAction != nil {
                Picker(L("Aktion"), selection: Binding(get: { button.pluginAction ?? "" }, set: { button.pluginAction = $0 })) {
                    ForEach(model.pluginActions) { a in Text(a.title).tag(a.id) }
                    if let id = button.pluginAction, !model.pluginActions.contains(where: { $0.id == id }) {
                        Text(id.isEmpty ? L("Keine Plugin-Aktionen – Plugins am Mac einschalten") : id + " " + L("(Plugin aus)")).tag(id)
                    }
                }
            } else if button.hold != nil {
                Picker(L("Taste"), selection: Binding(get: { button.hold ?? .shift }, set: { button.hold = $0 })) {
                    ForEach(HoldKey.allCases, id: \.self) { k in
                        Text(k == .space ? L("Leertaste") : k.symbol).tag(k)
                    }
                }
            } else {
                ShortcutEditor(shortcut: $button.shortcut)
            }
        }
        .themedForm()
        .navigationTitle(button.title)
    }
}

extension View {
    /// Settings pages on the app's background (flowing if switched on), rows slightly see-through.
    func themedForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(ThemeBackground().ignoresSafeArea())
    }
}

/// One profile or all profiles as a JSON file to share (AirDrop, Files, Messages, …).
struct ProfileExport: Transferable {
    var profiles: [SettingsProfile]
    init(profile: SettingsProfile) { profiles = [profile] }
    init(profiles: [SettingsProfile]) { self.profiles = profiles }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            let name = item.profiles.count == 1 ? item.profiles[0].name : "UniversePen profiles"
            let safe = name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "_" }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(String(safe) + ".universepen.json")
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = item.profiles.count == 1 ? try enc.encode(item.profiles[0]) : try enc.encode(item.profiles)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
