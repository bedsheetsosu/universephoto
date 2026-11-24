import SwiftUI
import TafelKit

/// The iPad's control centre: what used to be one long "…" list, as four tabs of big tiles.
/// It floats over the live picture, so it is a calm frosted panel that only moves when touched.
/// Tiles switch things without closing it; the next touch on the canvas closes it (a Pencil
/// stroke simply goes on).
struct CommandCenter: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject private var theme = Theme.shared
    let close: () -> Void
    let toggleStatus: () -> Void
    let showStatus: Bool
    let openSettings: () -> Void
    let openCheatSheet: () -> Void
    /// Height available on screen.
    var maxHeight: CGFloat = 600

    enum Tab: String, CaseIterable { case tools, source, clipboard, more }

    @AppStorage("commandCenterTab") private var tabRaw = Tab.tools.rawValue
    @AppStorage("perspectivePoints") private var perspectivePoints = 2
    @State private var contentHeight: CGFloat = 320
    @State private var windowsOpen = false

    private var tab: Binding<Tab> {
        Binding(get: { Tab(rawValue: tabRaw) ?? .tools }, set: { tabRaw = $0.rawValue })
    }

    private let four = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let two = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        let tabs: [(value: Tab, title: String, symbol: String?)] = [
            (.tools, L("Werkzeuge"), "pencil.and.ruler"),
            (.source, L("Quelle"), "display"),
            (.clipboard, L("Zwischenablage"), "doc.on.clipboard"),
            (.more, L("Mehr"), "ellipsis"),
        ]
        VStack(spacing: 12) {
            header
            UltraSegmented(tabs, selection: tab, collapsesTitles: true)
            ScrollView {
                Group {
                    switch tab.wrappedValue {
                    case .tools: tools
                    case .source: source
                    case .clipboard: clipboard
                    case .more: more
                    }
                }
                .padding(.bottom, 2)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            // As tall as its content, but never taller than the screen allows: the rest scrolls.
            .frame(height: min(max(contentHeight, 1), max(maxHeight - 132, 160)))
        }
        .padding(14)
        .frame(width: 372)
        .ultraPanel(Ultra.shape(Ultra.panelRadius))
        .animation(Ultra.smooth, value: contentHeight)
    }

    // MARK: Header

    private var macName: String {
        switch model.phase {
        case .connected(let n), .reconnecting(let n), .connecting(let n): return n
        default: return "Mac"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            let usb = model.timing?.link.hasPrefix("USB") ?? false
            Image(systemName: usb ? "cable.connector" : "wifi")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(usb ? Brand.mint : Color.orange)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.09), in: Circle())
                .accessibilityLabel(usb ? L("USB-Kabel") : L("WLAN"))
            VStack(alignment: .leading, spacing: 0) {
                Text(macName).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let t = model.timing {
                    Text("\(Int(t.rttMs.rounded())) ms · \(Int(t.fps.rounded())) fps")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    // MARK: Tools

    private func tool(_ t: IPadTool, closes: Bool = false) -> some View {
        UltraTile(t.shortTitle, symbol: t.symbol, on: model.isOn(t)) {
            model.runTool(t)
            if closes { close() }
        }
    }

    private var perspectiveOn: Bool {
        if case .perspective = model.guide { return true }
        return false
    }

    private var tools: some View {
        VStack(spacing: 12) {
            if !model.tabletModeActive {
                UltraHeader(L("Zeichenhilfen"))
                LazyVGrid(columns: four, spacing: 8) {
                    tool(.ruler)
                    UltraTile(L("Perspektive"), symbol: "perspective", on: perspectiveOn) {
                        let n = min(max(perspectivePoints, 1), 3)
                        model.guide = perspectiveOn ? .none : .perspective(n)
                        model.noteRecent(n == 1 ? .perspective1 : n == 2 ? .perspective2 : .perspective3)
                    }
                    tool(.ellipse)
                    tool(.grid)
                }
                aidOptions
            }
            UltraHeader(L("Strich"))
            LazyVGrid(columns: four, spacing: 8) {
                if !model.tabletModeActive {
                    tool(.shapeRecognition)
                    tool(.rope)
                }
                tool(.fixedPressure)
                tool(.speedPressure)
            }
            UltraHeader(L("Ansicht"))
            LazyVGrid(columns: four, spacing: 8) {
                if !model.tabletModeActive {
                    tool(.mirror)
                    tool(.grayscale)
                }
                UltraTile(L("Ausrichtung"), symbol: model.orientationLocked ? "lock.rotation" : "rotate.right",
                          on: model.orientationLocked) { model.toggleOrientationLock() }
                UltraTile(L("Status"), symbol: "gauge.with.dots.needle.33percent", on: showStatus || model.showStatusOverlay,
                          action: toggleStatus)
            }
            UltraHeader(L("Mac"))
            LazyVGrid(columns: four, spacing: 8) {
                tool(.laser)
                if !model.tabletModeActive {
                    tool(.palette, closes: true)
                    UltraTile(L("Foto"), symbol: "camera.viewfinder", enabled: !model.screenshotPending) {
                        model.requestScreenshot(); close()
                    }
                }
                UltraTile(L("Zeitraffer"), symbol: "timelapse") { model.session?.send(HostCommand.toggleTimelapse) }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .transition(.opacity)
    }

    private var lockButton: some View {
        UltraRoundButton(model.guidesLocked ? "lock.fill" : "lock.open",
                         label: model.guidesLocked ? L("Schablone entsperren") : L("Schablone sperren"), size: 36) {
            model.guidesLocked.toggle()
        }
    }

    /// Options and a one-line reminder for the aid that is on.
    @ViewBuilder private var aidOptions: some View {
        switch model.guide {
        case .ruler:
            hint(L("Lineal mit Fingern verschieben und drehen – Striche daran werden gerade"))
        case .perspective(let n):
            let counts: [(value: Int, title: String, symbol: String?)] = [(1, "1", nil), (2, "2", nil), (3, "3", nil)]
            HStack(spacing: 8) {
                Text(L("Fluchtpunkte")).font(.footnote.weight(.medium)).foregroundStyle(.secondary).padding(.leading, 4)
                UltraSegmented(counts, selection: Binding(get: { n }, set: {
                    perspectivePoints = $0
                    model.guide = .perspective($0)
                }))
                lockButton
            }
            hint(L("Fluchtpunkte mit dem Finger ziehen – jeder Strich folgt der passenden Fluchtlinie"))
        case .ellipse:
            HStack(spacing: 8) {
                hint(L("Innen verschieben, mit zwei Fingern drehen und skalieren, Knöpfe ändern die Achsen – Striche am Rand folgen der Ellipse"))
                lockButton
            }
        case .none:
            EmptyView()
        }
        if model.grid != .off {
            let styles: [(value: GridStyle, title: String, symbol: String?)] =
                [GridStyle.thirds, .quarters, .squares].map { (value: $0, title: $0.title, symbol: nil) }
            UltraSegmented(styles, selection: $model.grid)
        }
    }

    // MARK: Source

    private func modeTitle(_ id: String) -> String {
        switch id {
        case "display": return L("Ganzer Bildschirm")
        case "second-screen": return L("Zweiter Bildschirm")
        case "region": return L("iPad-Ausschnitt")
        case "window": return L("Fenster")
        default: return id
        }
    }

    private func modeSymbol(_ id: String) -> String {
        switch id {
        case "display": return "display"
        case "second-screen": return "rectangle.on.rectangle"
        case "region": return "ipad.landscape"
        default: return "macwindow"
        }
    }

    private var source: some View {
        VStack(spacing: 12) {
            if let l = model.sourceList {
                UltraHeader(L("Quelle"))
                LazyVGrid(columns: two, spacing: 8) {
                    ForEach(l.modes.filter { $0.id != "window" }) { m in
                        UltraTile(modeTitle(m.id), symbol: modeSymbol(m.id), on: l.mode == m.id, enabled: m.available, minHeight: 60) {
                            model.selectSource(SourceSelection(mode: m.id))
                        }
                    }
                    UltraTile(L("Fenster"), symbol: "macwindow", on: l.mode == "window", minHeight: 60) {
                        withAnimation(Ultra.smooth) { windowsOpen.toggle() }
                        if windowsOpen { model.selectSource(SourceSelection(refresh: true)) }
                    }
                }
                if windowsOpen {
                    VStack(spacing: 0) {
                        ForEach(l.windows) { w in
                            UltraRow(w.title, symbol: "macwindow", checked: l.mode == "window" && l.selectedWindow == w.id) {
                                model.selectSource(SourceSelection(mode: "window", window: w.id))
                            }
                        }
                        if l.windows.isEmpty { hint(L("Keine Fenster gefunden")) }
                    }
                }
                if l.displays.count > 1 {
                    UltraHeader(L("Bildschirm"))
                    VStack(spacing: 0) {
                        ForEach(l.displays) { d in
                            UltraRow(d.title, symbol: "display", checked: l.selectedDisplay == d.id) {
                                model.selectSource(SourceSelection(display: d.id))
                            }
                        }
                    }
                }
            }
            UltraHeader(L("Modus"))
            LazyVGrid(columns: two, spacing: 8) {
                UltraTile(L("Tablett-Modus"), symbol: "rectangle.dashed", on: model.settings.tabletMode, minHeight: 60) {
                    withAnimation(Brand.spring) { model.settings.tabletMode.toggle() }
                }
                UltraTile(L("Nur Monitor"), symbol: "eye", on: model.settings.viewOnly, minHeight: 60) {
                    withAnimation(Brand.spring) { model.settings.viewOnly.toggle() }
                    model.show(Toast(text: model.settings.viewOnly ? L("Nur Monitor – Eingaben gehen nicht an den Mac") : L("Eingabe wieder an"), seconds: 1.6))
                }
            }
            if model.tabletModeActive {
                VStack(spacing: 0) {
                    ForEach(model.allTabletPresets) { p in
                        UltraRow(p.title, symbol: p.appBundleID != nil ? "link" : "rectangle.dashed", detail: p.appName,
                                 checked: p.matches(model.tabletArea)) { model.applyTabletPreset(p) }
                    }
                    UltraRow(L("Aktiven Bereich anpassen"), symbol: "crop", trailing: "chevron.right") {
                        close()
                        withAnimation(Brand.spring) { model.tabletEditing = true }
                    }
                }
            }
            if let app = model.frontApp {
                UltraHeader(app.name)
                VStack(spacing: 0) {
                    UltraRow(L("Spielmodus"), symbol: "gamecontroller", checked: model.gameModeActive) { model.toggleGameMode() }
                    UltraRow(L("Tablett-Modus automatisch"), symbol: "wand.and.stars", checked: model.autoTabletForFrontApp) {
                        model.toggleAutoTablet()
                    }
                }
            }
            UltraHeader(L("Finger"))
            let modes: [(value: FingerMode, title: String, symbol: String?)] = [
                (.off, L("Aus"), nil), (.mouse, L("Maus"), nil), (.pen, L("Stift"), nil), (.pointer, L("Zeiger"), nil),
            ]
            UltraSegmented(modes, selection: $model.settings.fingerMode)
        }
    }

    // MARK: Clipboard

    private var clipboard: some View {
        VStack(spacing: 12) {
            UltraHeader(L("Zwischenablage"))
            LazyVGrid(columns: two, spacing: 8) {
                UltraTile(L("iPad → Mac"), symbol: "square.and.arrow.up.on.square", minHeight: 60) { model.copyClipboardToMac() }
                UltraTile(L("Mac → iPad"), symbol: "square.and.arrow.down.on.square", minHeight: 60) { model.fetchClipboardFromMac() }
            }
            UltraHeader(L("Eingabe"))
            LazyVGrid(columns: two, spacing: 8) {
                UltraTile(L("Referenzbild"), symbol: "photo.on.rectangle", on: model.reference.image != nil, minHeight: 60) {
                    close(); model.reference.pickerShown = true
                }
                UltraTile(L("Tastatur"), symbol: "keyboard", on: model.showKeyboard, minHeight: 60) {
                    model.showKeyboard.toggle(); close()
                }
            }
            if !model.settings.snippets.isEmpty {
                UltraHeader(L("Textbausteine"))
                VStack(spacing: 0) {
                    ForEach(Array(model.settings.snippets.enumerated()), id: \.offset) { _, text in
                        UltraRow(text, symbol: "text.quote") {
                            model.session?.send(text: text)
                            model.show(Toast(text: L("Am Mac getippt"), seconds: 1.2))
                        }
                    }
                }
            }
        }
    }

    // MARK: More

    private var more: some View {
        VStack(spacing: 12) {
            if model.profiles.count > 1 {
                UltraHeader(L("Profil"))
                VStack(spacing: 0) {
                    ForEach(model.profiles) { p in
                        UltraRow(p.name, symbol: "person.crop.square", checked: model.activeProfileID == p.id) {
                            if model.activeProfileID != p.id { withAnimation(Brand.spring) { model.switchProfile(p) } }
                        }
                    }
                }
            }
            if !model.pluginActions.isEmpty {
                UltraHeader(L("Plugins"))
                VStack(spacing: 0) {
                    ForEach(model.pluginActions) { a in
                        UltraRow(a.title, symbol: a.icon ?? "puzzlepiece.extension") { model.runPlugin(a.id); close() }
                    }
                }
            }
            UltraHeader("UniversePen")
            VStack(spacing: 0) {
                UltraRow(L("Gesten & Kürzel"), symbol: "hand.draw", trailing: "chevron.right") { close(); openCheatSheet() }
                UltraRow(L("Einstellungen …"), symbol: "gearshape", trailing: "chevron.right") { close(); openSettings() }
                UltraRow(L("Trennen"), symbol: "xmark", destructive: true) { close(); model.disconnect() }
            }
        }
    }
}
