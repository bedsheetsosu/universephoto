import SwiftUI
import TafelKit

/// Brings the main window forward, or opens it if it was closed. `openWindow(id:)` alone would
/// open a second window of the window group every time.
@MainActor func showMainWindow(_ openWindow: OpenWindowAction) {
    if let w = NSApp.windows.first(where: { ($0.identifier?.rawValue ?? "").hasPrefix("main") }) {
        if w.isMiniaturized { w.deminiaturize(nil) }
        w.makeKeyAndOrderFront(nil)
    } else {
        openWindow(id: "main")
    }
    NSApp.activate()
}

/// Menu bar commands of the Mac app. Static titles on purpose: the app's command builder must
/// not observe the controller (that would rebuild the menus on every change).
struct HostCommands: Commands {
    let host: HostController

    var body: some Commands {
        // One main window: "New window" would only open a second copy of it.
        CommandGroup(replacing: .newItem) {
            OpenMainCommand()
            PairCommand(host: host)
        }
        CommandMenu("iPad") {
            Button(L("Vorderstes Fenster aufs iPad")) { host.moveFrontWindowToIPad() }
            Button(L("Palette fürs iPad wählen …")) { host.pickPalette() }
            Button(L("Zeitraffer starten oder stoppen")) {
                host.timelapseRunning ? host.stopTimelapse() : host.startTimelapse()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            WindowCommand(title: L("Stifttest öffnen …"), id: "pentest")
            WindowCommand(title: L("Plugins …"), id: "plugins")
        }
    }
}

private struct OpenMainCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(L("UniversePen öffnen")) { showMainWindow(openWindow) }
            .keyboardShortcut("n")
    }
}

private struct PairCommand: View {
    @Environment(\.openWindow) private var openWindow
    let host: HostController
    var body: some View {
        Button(L("iPad koppeln …")) {
            showMainWindow(openWindow)
            host.beginPairing()
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])
    }
}

private struct WindowCommand: View {
    @Environment(\.openWindow) private var openWindow
    let title: String
    let id: String
    var body: some View {
        Button(title) {
            openWindow(id: id)
            NSApp.activate()
        }
    }
}
