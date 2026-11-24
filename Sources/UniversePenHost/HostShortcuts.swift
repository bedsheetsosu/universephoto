import AppIntents
import AppKit
import TafelKit

// Shortcuts / Spotlight actions of the Mac app. They act on the running controller, so a
// shortcut changes what the window, the menu bar and the iPad show right away.

struct HostShortcutError: Error, CustomLocalizedStringResourceConvertible {
    let localizedStringResource: LocalizedStringResource
}

@MainActor private func controller() throws -> HostController {
    guard let host = HostController.current else {
        throw HostShortcutError(localizedStringResource: "UniversePen Host is still starting. Try again in a moment.")
    }
    return host
}

enum HostSwitch: String, AppEnum {
    case on, off, toggle
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Switch"
    static let caseDisplayRepresentations: [HostSwitch: DisplayRepresentation] = [
        .on: "On", .off: "Off", .toggle: "Toggle",
    ]
    func apply(to value: Bool) -> Bool {
        switch self {
        case .on: true
        case .off: false
        case .toggle: !value
        }
    }
}

enum SourceChoice: String, AppEnum {
    case fullDisplay, secondScreen, iPadRegion, window
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Source"
    static let caseDisplayRepresentations: [SourceChoice: DisplayRepresentation] = [
        .fullDisplay: "Full display", .secondScreen: "Second screen", .iPadRegion: "iPad region", .window: "Window",
    ]
    var mode: CaptureMode {
        switch self {
        case .fullDisplay: .display
        case .secondScreen: .virtual
        case .iPadRegion: .region
        case .window: .window
        }
    }
}

struct PairIPadIntent: AppIntent {
    static let title: LocalizedStringResource = "Pair iPad"
    static let description = IntentDescription("Shows a pairing code in UniversePen Host for two minutes.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let host = try controller()
        NSApp.activate()
        NSApp.windows.first { ($0.identifier?.rawValue ?? "").hasPrefix("main") }?.makeKeyAndOrderFront(nil)
        host.beginPairing()
        return .result()
    }
}

struct SetSourceIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Source"
    static let description = IntentDescription("Chooses what the Mac sends to the iPad.")
    static let openAppWhenRun = false

    @Parameter(title: "Source", default: .fullDisplay) var source: SourceChoice

    @MainActor
    func perform() async throws -> some IntentResult {
        let host = try controller()
        if source == .secondScreen && !HostController.secondScreenAvailable {
            throw HostShortcutError(localizedStringResource: "This source is not available on this Mac.")
        }
        host.mode = source.mode
        return .result()
    }
}

struct TimelapseIntent: AppIntent {
    static let title: LocalizedStringResource = "Time-lapse"
    static let description = IntentDescription("Starts or stops recording the streamed picture as a time-lapse.")
    static let openAppWhenRun = false

    @Parameter(title: "Recording", default: .toggle) var state: HostSwitch

    @MainActor
    func perform() async throws -> some IntentResult {
        let host = try controller()
        let on = state.apply(to: host.timelapseRunning)
        guard on != host.timelapseRunning else { return .result() }
        if on {
            guard host.sessionDevice != nil else { throw HostShortcutError(localizedStringResource: "No iPad is connected.") }
            host.startTimelapse()
        } else {
            host.stopTimelapse()
        }
        return .result()
    }
}

/// One settings profile of the connected iPad.
struct IPadProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "iPad Profile"
    static let defaultQuery = IPadProfileQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct IPadProfileQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [IPadProfileEntity] {
        (HostController.current?.ipadProfiles ?? []).filter { identifiers.contains($0.id) }.map { IPadProfileEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [IPadProfileEntity] {
        (HostController.current?.ipadProfiles ?? []).map { IPadProfileEntity(id: $0.id, name: $0.name) }
    }
}

struct SwitchIPadProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch iPad Profile"
    static let description = IntentDescription("Makes one of the connected iPad's profiles the active one.")
    static let openAppWhenRun = false

    @Parameter(title: "Profile") var profile: IPadProfileEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let host = try controller()
        guard host.sessionDevice != nil else { throw HostShortcutError(localizedStringResource: "No iPad is connected.") }
        host.activateIPadProfile(profile.id)
        return .result()
    }
}

struct FrontWindowToIPadIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Front Window to iPad"
    static let description = IntentDescription("Moves the front window of the app you worked in last to what the iPad shows.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let host = try controller()
        guard host.sessionDevice != nil else { throw HostShortcutError(localizedStringResource: "No iPad is connected.") }
        host.moveFrontWindowToIPad()
        return .result()
    }
}

struct UniversePenHostShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PairIPadIntent(), phrases: [
            "Pair an iPad with \(.applicationName)",
        ], shortTitle: "Pair iPad", systemImageName: "ipad.and.arrow.forward")
        AppShortcut(intent: SetSourceIntent(), phrases: [
            "Set the source in \(.applicationName)",
        ], shortTitle: "Set Source", systemImageName: "rectangle.dashed.badge.record")
        AppShortcut(intent: TimelapseIntent(), phrases: [
            "Toggle the time-lapse in \(.applicationName)",
        ], shortTitle: "Time-lapse", systemImageName: "record.circle")
        AppShortcut(intent: SwitchIPadProfileIntent(), phrases: [
            "Switch the iPad profile in \(.applicationName)",
        ], shortTitle: "Switch iPad Profile", systemImageName: "person.crop.square")
        AppShortcut(intent: FrontWindowToIPadIntent(), phrases: [
            "Move the front window to the iPad with \(.applicationName)",
        ], shortTitle: "Window to iPad", systemImageName: "macwindow.badge.plus")
    }
}
