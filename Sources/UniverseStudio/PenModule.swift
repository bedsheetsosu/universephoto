import SwiftUI
import AppKit
import UniversePenHost

/// Runs the built-in UniversePen host when its module is switched on. The old stand-alone
/// UniversePen Host must not run at the same time (same ports, same iPad): the studio then
/// waits and offers to quit it.
@MainActor final class PenHost: ObservableObject {
    static let shared = PenHost()
    @Published private(set) var running = false
    @Published private(set) var standaloneRunning = false
    private var watch: Timer?

    /// Starts the host if the module is on and the old app is not running.
    func startIfWanted() {
        guard ModuleSettings.isEnabled(.pen), !running else { return }
        standaloneRunning = UniversePenModule.standaloneApp != nil
        if standaloneRunning { watchStandalone(); return }
        UniversePenModule.start()
        running = UniversePenModule.isRunning
    }

    /// Asks the old app to quit (it may ask about unsaved state itself), then starts here.
    func quitStandalone() {
        UniversePenModule.standaloneApp?.terminate()
        watchStandalone()
    }

    private func watchStandalone() {
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in PenHost.shared.checkStandalone() }
        }
    }

    private func checkStandalone() {
        guard UniversePenModule.standaloneApp == nil else { return }
        watch?.invalidate(); watch = nil
        standaloneRunning = false
        startIfWanted()
    }
}

/// Which modules the user switched on in the setup (stored as "photo,pen").
enum ModuleSettings {
    static let key = "studioModules", setupKey = "studioSetupDone"
    static func enabled(_ raw: String? = UserDefaults.standard.string(forKey: key)) -> [StudioModule] {
        guard let raw else { return [.photo, .animate] }
        let names = raw.split(separator: ",").map(String.init)
        // Animate came out of Photo in 0.106: whoever had Photo gets Animate unless they turned it off.
        return StudioModule.allCases.filter { names.contains($0.rawValue) || ($0 == .animate && names.contains("photo") && !names.contains("!animate")) }
    }
    static func isEnabled(_ m: StudioModule) -> Bool { enabled().contains(m) }
    static func store(_ ms: Set<StudioModule>) -> String { (StudioModule.allCases.filter(ms.contains).map(\.rawValue) + (ms.contains(.animate) ? [] : ["!animate"])).joined(separator: ",") }
}

/// The UniversePen module page: the host's own window content with a way back.
struct PenModuleView: View {
    @EnvironmentObject var s: Studio
    @ObservedObject private var pen = PenHost.shared
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if pen.running { UniversePenModule.mainView() }
            else { PenWaitingView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.08)) }
            Button { s.showStartScreen() } label: { Label(L("Start screen"), systemImage: "square.grid.2x2") }
                .buttonStyle(.borderless).padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule()).padding(.top, 12).padding(.trailing, 16)
                .help(L("Start screen") + " · ⇧⌘H")
        }
    }
}

/// Shown while the old stand-alone app still runs (or the module is off).
struct PenWaitingView: View {
    @ObservedObject private var pen = PenHost.shared
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "pencil.tip.crop.circle.badge.exclamationmark").font(.system(size: 40)).foregroundStyle(.secondary)
            if pen.standaloneRunning {
                Text(L("The old UniversePen Host app is still running.")).font(.headline)
                Text(L("UniverseStudio now contains UniversePen. Both cannot run at the same time; quit the old app to use it here.")).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
                Button(L("Quit old app and continue here")) { pen.quitStandalone() }.buttonStyle(.borderedProminent)
            } else {
                Text(L("UniversePen is switched off.")).font(.headline)
                Text(L("Switch it on in the setup (start screen → Set up modules).")).foregroundStyle(.secondary)
            }
        }.padding(30)
    }
}
