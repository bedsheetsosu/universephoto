import SwiftUI
import TafelKit

/// First-run setup: a short assistant that asks what you want to do and with which Pencil, then
/// only shows the pages that matter and sets everything up (incl. profiles when you want both).
/// Everything chosen here can be changed later in Settings.
struct OnboardingView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    /// `-debugOnboardingStep N` starts on page N (for screenshots).
    @State private var step = UserDefaults.standard.integer(forKey: "debugOnboardingStep")
    @State private var forward = true

    enum Use: Hashable { case drawing, tablet, both }
    enum PencilKind: Hashable { case pro, hover, noHover }
    enum AreaSize: Hashable { case full, medium, small }

    @State private var use: Use = .drawing
    @State private var pencilKind: PencilKind = .pro
    // Tablet choices (applied to the tablet profile at the end)
    @State private var areaSize: AreaSize = .medium
    @State private var keysOn = true
    @State private var keysSide: TabletKeys.Side = .left
    @State private var tip: Double = 0

    private enum Page: Hashable { case language, welcome, connection, use, pencil, fingers, drawing, tablet, look, done }

    private var pages: [Page] {
        var p: [Page] = [.language, .welcome, .connection, .use, .pencil]
        if use != .tablet { p += [.fingers, .drawing] }
        if use != .drawing { p.append(.tablet) }
        p += [.look, .done]
        return p
    }

    var body: some View {
        ZStack {
            ThemeBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    page(pages[min(step, pages.count - 1)])
                        .id(pages[min(step, pages.count - 1)])
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: 680, maxHeight: .infinity)
                .padding(.horizontal, 28)
                footer
            }
        }
        .animation(Ultra.smooth, value: step)
        .sensoryFeedback(.selection, trigger: step)
    }

    @ViewBuilder private func page(_ p: Page) -> some View {
        switch p {
        case .language: language
        case .welcome: welcome
        case .connection: connection
        case .use: usePage
        case .pencil: pencil
        case .fingers: fingers
        case .drawing: drawing
        case .tablet: tablet
        case .look: look
        case .done: done
        }
    }

    // MARK: Footer: progress + navigation

    private var footer: some View {
        HStack {
            Button { go(-1) } label: {
                Label(L("Zurück"), systemImage: "chevron.left")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .ultraGlass(Capsule(), interactive: true)
                    .contentShape(Capsule())
            }
            .buttonStyle(UltraPress())
            .opacity(step == 0 ? 0 : 1)
            .disabled(step == 0)
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? AnyShapeStyle(Ultra.accentFill) : AnyShapeStyle(Color.white.opacity(i < step ? 0.45 : 0.2)))
                        .frame(width: i == step ? 26 : 8, height: 8)
                }
            }
            Spacer()
            Button {
                if step == pages.count - 1 { finish() } else { go(1) }
            } label: {
                HStack(spacing: 8) {
                    Text(step == pages.count - 1 ? L("Los geht’s") : L("Weiter"))
                    Image(systemName: step == pages.count - 1 ? "checkmark" : "arrow.right")
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.callout.weight(.bold))
                .foregroundStyle(Brand.slateDeep)
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background(Ultra.accentFill, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: Brand.mint.opacity(0.5), radius: 14, y: 3)
            }
            .buttonStyle(UltraPress())
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private func go(_ d: Int) {
        forward = d > 0
        step = max(0, min(pages.count - 1, step + d))
    }

    // MARK: Pages

    private var language: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Brand.mint)
            Text("Language · Sprache")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Choose your language. · Wähle deine Sprache.")
                .font(.title3).foregroundStyle(.secondary)
            LanguageChoice().frame(maxWidth: 560)
            Spacer()
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                PulseRings(color: Brand.mint).frame(width: 150, height: 150)
                TafelMark().frame(width: 120, height: 120)
                    .shadow(color: Brand.mint.opacity(0.4), radius: 30)
            }
            Text(L("Willkommen bei UniversePen"))
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text(L("Dein iPad wird zum Zeichendisplay für den Mac – mit Pencil-Druck und Neigung, Fingern, Tastatur und Trackpad. Ohne Konto, ohne Cloud, kostenlos."))
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(L("Ein paar Fragen, dann passt alles. Du kannst später alles in den Einstellungen ändern."))
                .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var connection: some View {
        PageScaffold(symbol: "cable.connector", title: L("So verbindet sich UniversePen"),
                     subtitle: L("Auf dem Mac läuft die App „UniversePen Host“. Beim ersten Mal koppelst du beide mit einem Code.")) {
            InfoRow(symbol: "cable.connector", title: L("USB-Kabel (empfohlen)"),
                    text: L("Geringste Latenz. UniversePen nimmt automatisch das Kabel, sobald es steckt."))
            InfoRow(symbol: "wifi", title: L("WLAN"),
                    text: L("Funktioniert auch ohne Kabel, wenn Mac und iPad im selben WLAN sind."))
            InfoRow(symbol: "lock.shield", title: L("Verschlüsselt und privat"),
                    text: L("Nur gekoppelte Geräte, direkt zwischen Mac und iPad – keine Server."))
            InfoRow(symbol: "network", title: L("Lokales Netzwerk"),
                    text: L("iPadOS fragt gleich, ob UniversePen Geräte im lokalen Netzwerk finden darf. Bitte erlauben – sonst findet das iPad den Mac nicht."))
        }
    }

    private var usePage: some View {
        PageScaffold(symbol: "sparkles", title: L("Wofür nutzt du UniversePen?"),
                     subtitle: L("Danach zeigen wir nur, was dazu passt.")) {
            BigChoice(symbol: "paintbrush.pointed", title: L("Zeichnen"),
                      text: L("Das iPad zeigt den Mac – du zeichnest direkt aufs Bild, wie auf einem Cintiq."),
                      on: use == .drawing) { use = .drawing }
            BigChoice(symbol: "scope", title: L("Spielen und Zielen"),
                      text: L("Tablett-Modus wie ein Intuos: schwarze Fläche mit aktivem Bereich, kein Bild, minimale Latenz – z. B. für osu!."),
                      on: use == .tablet) { use = .tablet }
            BigChoice(symbol: "square.split.2x1", title: L("Beides"),
                      text: L("Zwei Profile „Zeichnen“ und „Spielen“, im Menü unter „Mehr“ mit einem Tipp umschaltbar."),
                      on: use == .both) { use = .both }
        }
    }

    private var pencil: some View {
        PageScaffold(symbol: "applepencil.tip", title: L("Dein Pencil"),
                     subtitle: L("Welchen Pencil benutzt du? Danach stellen wir Schweben, Squeeze und Klicken passend ein.")) {
            ChoiceRow(title: L("Modell"), options: [
                (L("Pencil Pro"), "applepencil.and.scribble", PencilKind.pro),
                (L("Mit Schweben"), "applepencil.tip", PencilKind.hover),
                (L("Ohne Schweben"), "applepencil", PencilKind.noHover),
            ], selected: pencilKind) { k in
                pencilKind = k
                model.settings.sendHover = k != .noHover
                model.settings.doubleTapToClick = k == .noHover
                if k == .noHover && model.settings.fingerMode == .mouse { model.settings.fingerMode = .pointer }
                if k == .pro && model.settings.squeeze == .undo { model.settings.squeeze = .radialMenu }
            }
            Text(pencilHelp).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ChoiceRow(title: L("Druckgefühl"), options: [
                (L("Weich"), "feather", 0.6), (L("Normal"), "pencil", 1.0), (L("Fest"), "pencil.tip", 1.6),
            ], selected: closest(model.settings.pressure.gamma, in: [0.6, 1.0, 1.6])) { model.settings.pressure.gamma = $0; model.settings.pressure.points = [] }
            if pencilKind != .noHover {
                ActionChoice(title: L("Doppeltippen"), action: $model.settings.doubleTap)
            }
            if pencilKind == .pro {
                ActionChoice(title: L("Squeeze"), action: $model.settings.squeeze)
            }
        }
    }

    private var pencilHelp: String {
        switch pencilKind {
        case .pro: return L("Schweben, Barrel Roll, Squeeze und Haptik. Squeeze öffnet das Radialmenü an der Stiftspitze.")
        case .hover: return L("Pencil 2 auf einem iPad mit Schweben: der Zeiger folgt dem Stift, bevor er aufsetzt.")
        case .noHover: return L("Ohne Schweben: Eine Berührung bewegt nur den Zeiger, sofort nochmal aufsetzen klickt bzw. zeichnet. Ein Finger zielt ohne zu klicken.")
        }
    }

    private var fingers: some View {
        PageScaffold(symbol: "hand.point.up.left", title: L("Und deine Finger?"),
                     subtitle: L("Wie bei einem Stift-Display. Liegt der Pencil in der Nähe, ignoriert UniversePen die Hand.")) {
            ChoiceRow(title: L("Ein Finger"), options: [
                (L("Maus"), "cursorarrow.click", FingerMode.mouse),
                (L("Stift"), "scribble", FingerMode.pen),
                (L("Zeiger"), "hand.point.up", FingerMode.pointer),
                (L("Aus"), "hand.raised.slash", FingerMode.off),
            ], selected: model.settings.fingerMode) { model.settings.fingerMode = $0 }
            Text(fingerHelp).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
            FeatureToggle(symbol: "arrow.uturn.backward", title: L("Undo-Wischen"),
                          text: L("Zwei Finger kurz halten, dann nach links ziehen = Undo, rechts = Redo."),
                          on: $model.settings.undoScrub)
            InfoRow(symbol: "hand.draw", title: L("Zwei Finger"),
                    text: L("Verschieben = Scrollen, Pinch = Zoomen, Tippen = Widerrufen."))
            InfoRow(symbol: "hand.wave", title: L("Drei Finger"),
                    text: L("Links/rechts wischen = Schreibtisch wechseln, oben = Mission Control, unten = App-Fenster."))
        }
    }

    private var fingerHelp: String {
        switch model.settings.fingerMode {
        case .mouse: return L("Tippen = Klick, Ziehen = Klicken und Ziehen, Halten = Rechtsklick.")
        case .pen: return L("Ein Finger zeichnet wie der Pencil, mit festem Druck. Halten = Rechtsklick.")
        case .off: return L("Ein Finger macht nichts – nur Gesten mit mehreren Fingern.")
        case .pointer: return L("Ein Finger bewegt nur den Zeiger, Tippen = Klick, Halten = Rechtsklick. Gut für Pencils ohne Schweben: mit dem Finger zielen, mit dem Stift zeichnen.")
        }
    }

    private var drawing: some View {
        PageScaffold(symbol: "paintbrush.pointed", title: L("Zum Zeichnen"),
                     subtitle: L("Was das iPad beim Zeichnen zusätzlich macht. Alles später in den Einstellungen änderbar.")) {
            FeatureToggle(symbol: "scribble.variable", title: L("Sofort-Tinte"),
                          text: L("Der Strich erscheint sofort auf dem iPad und blendet aus, wenn das echte Bild vom Mac da ist – fühlt sich direkter an."),
                          on: $model.settings.instantInk)
            if pencilKind != .noHover {
                FeatureToggle(symbol: "smallcircle.filled.circle", title: L("Hover-Punkt"),
                              text: L("Ein kleiner Ring unter der schwebenden Stiftspitze zeigt genau, wo du ansetzt."),
                              on: $model.settings.hoverDot)
            }
            FeatureToggle(symbol: "sidebar.leading", title: L("Shortcut-Leiste"),
                          text: L("Tasten wie Undo, Pinsel, Radierer und ⇧ / ⌥ zum Halten am Rand."),
                          on: $model.settings.showShortcutBar)
            if model.settings.showShortcutBar {
                ChoiceRow(title: L("Zeichenhand"), options: [
                    (L("Rechts"), "hand.point.right", false), (L("Links"), "hand.point.left", true),
                ], selected: model.settings.shortcutBarOnRight) { model.settings.shortcutBarOnRight = $0 }
            }
            ChoiceRow(title: L("Bildqualität"), options: QualityPreset.allCases.map { ($0.title, $0.symbol, $0) },
                      selected: QualityPreset(matching: model.quality)) { model.quality = $0.apply(to: model.quality) }
            Text(QualityPreset(matching: model.quality)?.detail ?? L("Eigene Einstellung"))
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            FeatureToggle(symbol: "speaker.wave.2", title: L("Ton vom Mac auf dem iPad"),
                          text: L("Der Mac spielt den Ton weiter selbst ab."), on: $model.quality.audio)
        }
    }

    private var tablet: some View {
        PageScaffold(symbol: "scope", title: L("Tablett-Modus"),
                     subtitle: L("Wie ein Intuos: das iPad wird schwarz, der aktive Bereich wird auf den ganzen Mac-Bildschirm abgebildet.")) {
            ChoiceRow(title: L("Aktiver Bereich"), options: [
                (L("Ganze Fläche"), "rectangle", AreaSize.full),
                (L("Mittel"), "rectangle.inset.filled", AreaSize.medium),
                (L("Klein"), "smallcircle.filled.circle", AreaSize.small),
            ], selected: areaSize) { areaSize = $0 }
            Text(L("Kleiner Bereich = kurze Wege für schnelles Zielen (typisch für osu!). Genau einstellen und als Preset speichern kannst du später im Menü unter „Quelle“."))
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            FeatureToggle(symbol: "keyboard", title: L("Tasten-Feld Z / X"),
                          text: L("Große Touch-Tasten am Rand, mit der anderen Hand halten – wie ExpressKeys."), on: $keysOn)
            if keysOn {
                ChoiceRow(title: L("Seite"), options: [
                    (L("Links"), "rectangle.lefthalf.filled", TabletKeys.Side.left),
                    (L("Rechts"), "rectangle.righthalf.filled", TabletKeys.Side.right),
                    (L("Oben"), "rectangle.tophalf.filled", TabletKeys.Side.top),
                    (L("Unten"), "rectangle.bottomhalf.filled", TabletKeys.Side.bottom),
                ], selected: keysSide) { keysSide = $0 }
            }
            ChoiceRow(title: L("Klick ab Druck"), options: [
                (L("Sofort"), "hand.tap", 0.0), (L("Leicht"), "dial.low", 0.12), (L("Fest"), "dial.high", 0.3),
            ], selected: closest(tip, in: [0, 0.12, 0.3])) { tip = $0 }
            InfoRow(symbol: "gamecontroller", title: L("Tipp für osu!"),
                    text: L("In osu! unter Input → Mouse „High precision mouse“ ausschalten, sonst springt der Cursor."))
        }
    }

    private var look: some View {
        PageScaffold(symbol: "paintpalette", title: L("Aussehen"),
                     subtitle: L("Deine Farbe für die App – auf Wunsch mit fließendem Hintergrund.")) {
            ThemeChoice().tafelCard(padding: 16)
        }
    }

    private var done: some View {
        PageScaffold(symbol: "checkmark.seal", title: L("Alles bereit"),
                     subtitle: L("So ist UniversePen jetzt eingestellt:")) {
            if use != .tablet {
                InfoRow(symbol: "paintbrush.pointed", title: use == .both ? L("Profil „Zeichnen“") : L("Zeichnen"),
                        text: summaryDrawing)
            }
            if use != .drawing {
                InfoRow(symbol: "scope", title: use == .both ? L("Profil „Spielen“") : L("Tablett-Modus"),
                        text: summaryTablet)
            }
            if use == .both {
                InfoRow(symbol: "person.crop.square", title: L("Umschalten"),
                        text: L("Im Menü oben rechts unter „Mehr“ → „Profil“. Änderungen landen automatisch im aktiven Profil."))
            }
            InfoRow(symbol: "gearshape", title: L("Alles änderbar"),
                    text: L("Jede Einstellung findest du später im Menü oben rechts unter „Mehr“ → „Einstellungen …“, ohne Verbindung über das Zahnrad. Die Einrichtung kannst du dort auch neu starten."))
        }
    }

    private var summaryDrawing: String {
        var parts: [String] = []
        parts.append(model.settings.instantInk ? L("Sofort-Tinte an") : L("Sofort-Tinte aus"))
        if model.settings.showShortcutBar { parts.append(L("Shortcut-Leiste")) }
        if let q = QualityPreset(matching: model.quality) { parts.append(q.title) }
        if pencilKind == .pro { parts.append(L("Squeeze: %@", model.settings.squeeze.display)) }
        if pencilKind == .noHover { parts.append(L("Doppeltippen zum Klicken")) }
        return parts.joined(separator: " · ")
    }

    private var summaryTablet: String {
        let area: String
        switch areaSize {
        case .full: area = L("Ganze Fläche")
        case .medium: area = L("Mittel")
        case .small: area = L("Klein")
        }
        var parts = [area]
        if keysOn { parts.append(L("Tasten Z / X")) }
        if tip > 0 { parts.append(L("Klick ab %d %% Druck", Int(tip * 100))) }
        return parts.joined(separator: " · ")
    }

    // MARK: Finish

    /// Applies the tablet choices and creates profiles when both uses were chosen.
    private func finish() {
        // Opened from the Mac for a UI check (launch arguments): never rewrite settings or
        // profiles of a device that is already set up.
        if ProcessInfo.processInfo.arguments.contains("-debugOnboardingStep") {
            model.onboardingDone = true
            return
        }
        func tabletVersion(of base: InputSettings) -> InputSettings {
            var t = base
            t.tabletMode = true
            switch areaSize {
            case .full: t.tabletArea = .full; t.tabletLockAspect = false
            case .medium: t.tabletArea = TabletArea(x: 0.2, y: 0.2, width: 0.6, height: 0.6); t.tabletLockAspect = true
            case .small: t.tabletArea = TabletArea(x: 0.3, y: 0.3, width: 0.4, height: 0.4); t.tabletLockAspect = true
            }
            t.tabletKeys.enabled = keysOn
            t.tabletKeys.side = keysSide
            t.tipThreshold = tip
            return t
        }
        switch use {
        case .drawing:
            model.settings.tabletMode = false
        case .tablet:
            model.settings = tabletVersion(of: model.settings)
        case .both:
            var drawing = model.settings
            drawing.tabletMode = false
            let gaming = tabletVersion(of: model.settings)
            let pDraw = SettingsProfile(name: L("Zeichnen"), settings: drawing, quality: model.quality)
            let pGame = SettingsProfile(name: L("Spielen"), settings: gaming, quality: model.quality)
            model.profiles.removeAll { $0.name == pDraw.name || $0.name == pGame.name }
            model.profiles += [pDraw, pGame]
            model.switchProfile(pDraw)
        }
        model.onboardingDone = true
    }

    private func closest(_ v: Double, in options: [Double]) -> Double? {
        options.min(by: { abs($0 - v) < abs($1 - v) })
    }
}

// MARK: - Quality presets

enum QualityPreset: CaseIterable, Hashable {
    case best, balanced, smooth

    var title: String {
        switch self {
        case .best: return L("Beste")
        case .balanced: return L("Ausgewogen")
        case .smooth: return L("Flüssig")
        }
    }
    var symbol: String {
        switch self {
        case .best: return "sparkles"
        case .balanced: return "dial.medium"
        case .smooth: return "hare"
        }
    }
    var detail: String {
        switch self {
        case .best: return L("HEVC, 50 Mbit/s, 60 fps, volle iPad-Auflösung – ideal mit Kabel.")
        case .balanced: return L("H.264, 30 Mbit/s, 60 fps, volle Auflösung.")
        case .smooth: return L("H.264, 15 Mbit/s, 60 fps, 75 % Auflösung – für schwaches WLAN.")
        }
    }
    private var values: (VideoCodec, Double, Int, Double) {
        switch self {
        case .best: return (.hevc, 50, 60, 1)
        case .balanced: return (.h264, 30, 60, 1)
        case .smooth: return (.h264, 15, 60, 0.75)
        }
    }
    init?(matching q: StreamQuality) {
        guard let p = Self.allCases.first(where: { let v = $0.values; return q.codec == v.0 && q.bitrateMbps == v.1 && q.fps == v.2 && q.resolutionScale == v.3 })
        else { return nil }
        self = p
    }
    func apply(to q: StreamQuality) -> StreamQuality {
        var q = q
        (q.codec, q.bitrateMbps, q.fps, q.resolutionScale) = values
        return q
    }
}

// MARK: - Building blocks

private struct PageScaffold<Content: View>: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Brand.slateDeep)
                    .symbolEffect(.bounce, value: shown)
                    .frame(width: 68, height: 68)
                    .background(Ultra.accentFill, in: Ultra.shape(20))
                    .overlay(Ultra.shape(20).strokeBorder(.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: Brand.mint.opacity(0.5), radius: 18, y: 5)
                    .scaleEffect(shown ? 1 : 0.6)
                    .padding(.top, 56)
                Text(title).font(.system(size: 36, weight: .bold, design: .rounded))
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                content
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onAppear { withAnimation(Ultra.bouncy.delay(0.12)) { shown = true } }
    }
}

private struct InfoRow: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(Brand.mint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
        .tafelCard(padding: 14)
    }
}

/// Big tappable choice tiles.
private struct ChoiceRow<Value: Hashable>: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let title: String
    let options: [(String, String, Value)]
    let selected: Value?
    let choose: (Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Brand.mintBright)
            HStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { i in
                    let (label, symbol, value) = options[i]
                    let on = value == selected
                    Button {
                        withAnimation(Brand.spring) { choose(value) }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: symbol)
                                .font(.system(size: 24))
                                .symbolEffect(.bounce, value: on)
                            Text(label).font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(on ? Brand.slateDeep : .primary)
                        .ultraChoice(Ultra.shape(18), on: on)
                    }
                    .buttonStyle(UltraPress())
                }
            }
        }
    }
}

/// Large selectable card with icon, title and explanation.
private struct BigChoice: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let symbol: String
    let title: String
    let text: String
    let on: Bool
    let choose: () -> Void

    var body: some View {
        Button {
            withAnimation(Brand.spring) { choose() }
        } label: {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 40)
                    .symbolEffect(.bounce, value: on)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(text).font(.callout).opacity(0.8).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(on ? Brand.slateDeep : .primary)
            .ultraChoice(Ultra.shape(Ultra.cardRadius), on: on)
        }
        .buttonStyle(UltraPress(scale: 0.97))
    }
}

/// Feature card with a switch.
private struct FeatureToggle: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let symbol: String
    let title: String
    let text: String
    @Binding var on: Bool

    var body: some View {
        Toggle(isOn: $on.animation(Brand.spring)) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3).foregroundStyle(on ? Brand.mint : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .tint(Brand.mint)
        .tafelCard(padding: 14)
    }
}

/// Compact choice of the common Pencil actions.
private struct ActionChoice: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let title: String
    @Binding var action: PencilAction

    private let options: [(String, PencilAction)] = [
        (L("Radialmenü"), .radialMenu), (L("Radierer"), .eraser), (L("Widerrufen"), .undo), (L("Pinsel"), .brush), (L("Hand"), .hand),
        (L("Nichts"), .none),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Brand.mintBright)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options.indices, id: \.self) { i in
                        let (label, value) = options[i]
                        let on = value == action
                        Button {
                            withAnimation(Brand.spring) { action = value }
                        } label: {
                            Text(label)
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .foregroundStyle(on ? Brand.slateDeep : .primary)
                                .ultraChoice(Capsule(), on: on)
                        }
                        .buttonStyle(UltraPress())
                    }
                }
            }
        }
    }
}
