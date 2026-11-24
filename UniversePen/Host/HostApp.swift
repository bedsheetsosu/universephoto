import SwiftUI
import TafelKit

@main
struct TafelHostApp: App {
    // @State, not @StateObject: the App itself must not re-run on every change of the controller
    // (that redraws the menu bar icon on every display each time); the views observe it themselves.
    @State private var host = HostController()

    init() { Self.migrateOldDefaults() }

    /// The app was called "Tafel Host" (bundle ID local.tafel.host). Take its settings over once,
    /// before anything reads them, so mode, developer API switch etc. survive the rename.
    /// Pairing keys live in the keychain (service "Tafel") and are not affected by the bundle ID;
    /// macOS may ask once whether the renamed app may read them.
    private static func migrateOldDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromTafelHost"), let id = Bundle.main.bundleIdentifier, id != "local.tafel.host" else { return }
        if let old = d.persistentDomain(forName: "local.tafel.host"), !old.isEmpty {
            var merged = old
            for (k, v) in d.persistentDomain(forName: id) ?? [:] { merged[k] = v }   // never overwrite newer values
            d.setPersistentDomain(merged, forName: id)
        }
        d.set(true, forKey: "migratedFromTafelHost")
    }

    var body: some Scene {
        WindowGroup("UniversePen", id: "main") {
            HostView()
                .environmentObject(host)
                .onOpenURL { host.handle(url: $0) }
                .frame(minWidth: 780, idealWidth: 860, minHeight: 560, idealHeight: 660)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 660)
        .commands { HostCommands(host: host) }

        Window(L("Stifttest"), id: "pentest") {
            PenTestView()
        }

        Window(L("Plugins"), id: "plugins") {
            PluginsWindow().environmentObject(host)
        }

        MenuBarExtra {
            HostMenuPanel().environmentObject(host)
        } label: {
            MenuBarIcon(state: host.menuIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var state: MenuIconState
    var body: some View {
        // While a time-lapse records, the icon carries a record mark (like the screen recording
        // indicator), so a forgotten recording is visible.
        Image(systemName: state.recording ? "record.circle"
              : state.lowBattery ? "battery.0percent" : state.connected ? "pencil.tip.crop.circle.fill" : "pencil.tip")
            .accessibilityLabel(state.recording ? L("UniversePen – Zeitraffer läuft")
                                : state.connected ? L("UniversePen – verbunden") : "UniversePen")
    }
}
