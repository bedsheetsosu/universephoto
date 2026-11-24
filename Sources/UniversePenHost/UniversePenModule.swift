import SwiftUI
import AppKit
import TafelKit

/// The UniversePen Mac host, built into UniverseStudio. This is the only public surface of the
/// module: the studio decides when the host runs and where its views appear.
@MainActor
public enum UniversePenModule {
    /// Set by the studio: brings its window forward and shows this module (replaces "open the
    /// UniversePen window" everywhere in the host code).
    public static var showInStudio: (() -> Void)?

    /// Bundle ID of the old stand-alone app; it must not run at the same time (same ports, same iPad).
    public static let standaloneBundleID = "local.universepen.host"
    static let legacyBundleIDs = ["local.universepen.host", "local.tafel.host"]
    static let migratedKey = "migratedFromUniversePenHost"

    private static var controller: HostController?

    /// Whether the host is running inside the studio.
    public static var isRunning: Bool { controller != nil }

    /// Starts the host (server, Bonjour, developer API). Call only while the old app is not running.
    public static func start() {
        guard controller == nil else { return }
        migrateDefaults(into: .standard)
        controller = HostController()
    }

    /// The old stand-alone UniversePen Host, if it is running.
    public static var standaloneApp: NSRunningApplication? {
        legacyBundleIDs.lazy.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }.first
    }

    /// Copies the old app's settings (host ID, mode, plugins …) over once. The iPad knows this Mac
    /// by its host ID, so it has to stay the same. New values are never overwritten.
    @discardableResult
    public static func migrateDefaults(into d: UserDefaults, from domains: [[String: Any]]? = nil) -> Int {
        guard !d.bool(forKey: migratedKey) else { return 0 }
        let sources = domains ?? legacyBundleIDs.compactMap { d.persistentDomain(forName: $0) }
        var copied = 0
        for domain in sources {
            for (k, v) in domain where d.object(forKey: k) == nil && !k.hasPrefix("NS") && k != "AppleLanguages" && !k.hasPrefix("debug") {
                d.set(v, forKey: k); copied += 1
            }
        }
        d.set(true, forKey: migratedKey)
        return copied
    }

    /// Keeps the host's language in step with the studio's (the host knows more languages).
    public static func setLanguage(_ code: String) {
        if let l = AppLanguage(rawValue: code), L10n.shared.language != l { L10n.shared.language = l }
    }

    // MARK: Views

    /// The full UniversePen window content (pages, status, settings).
    public static func mainView() -> some View { Root { HostView() } }
    /// The menu bar panel.
    public static func menuPanel() -> some View { Root { HostMenuPanel() } }
    @ViewBuilder public static func menuIcon() -> some View {
        // Observes only the icon state, not the whole controller (that would redraw the menu bar on every change).
        if let c = controller { MenuBarIcon(state: c.menuIcon) } else { Image(systemName: "pencil.tip") }
    }
    public static func penTestView() -> some View { PenTestView() }
    public static func pluginsView() -> some View { Root { PluginsWindow() } }
    /// The host's own setup (permissions, source, pairing) for the studio's first-run setup.
    public static func setupView(done: Binding<Bool>) -> some View { Root { HostOnboarding(done: done) } }
    public static var setupDone: Bool { UserDefaults.standard.bool(forKey: "hostOnboardingDone") }

    public static func handle(url: URL) { controller?.handle(url: url) }

    // MARK: Commands

    public static func beginPairing() { controller?.beginPairing() }
    public static func moveFrontWindowToIPad() { controller?.moveFrontWindowToIPad() }
    public static func pickPalette() { controller?.pickPalette() }
    public static func toggleTimelapse() {
        guard let c = controller else { return }
        c.timelapseRunning ? c.stopTimelapse() : c.startTimelapse()
    }

    /// Wraps a host view with the controller it needs; empty while the host is not running.
    private struct Root<Content: View>: View {
        @ViewBuilder var content: () -> Content
        var body: some View {
            if let c = UniversePenModule.controller { content().environmentObject(c) }
        }
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var state: MenuIconState
    var body: some View {
        Image(systemName: state.recording ? "record.circle"
              : state.lowBattery ? "battery.0percent" : state.connected ? "pencil.tip.crop.circle.fill" : "pencil.tip")
            .accessibilityLabel(state.recording ? L("UniversePen – Zeitraffer läuft")
                                : state.connected ? L("UniversePen – verbunden") : "UniversePen")
    }
}
