import AppIntents
import TafelKit

// Shortcuts / Siri / Spotlight actions. Everything acts on the one shared ClientModel, so an
// action run while the app is open changes what is on screen right away. Control Center:
// add the system "Shortcut" control and pick one of these (no widget extension needed).

/// A paired Mac.
struct MacEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mac"
    static let defaultQuery = MacQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct MacQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MacEntity] {
        ClientModel.shared.paired.filter { identifiers.contains($0.id) }.map { MacEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MacEntity] {
        ClientModel.shared.paired.map { MacEntity(id: $0.id, name: $0.name) }
    }
}

enum Switch: String, AppEnum {
    case on, off, toggle
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Switch"
    static let caseDisplayRepresentations: [Switch: DisplayRepresentation] = [
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

struct ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    let localizedStringResource: LocalizedStringResource
}

struct ConnectToMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect to Mac"
    static let description = IntentDescription("Connects to a paired Mac as soon as it is found.")
    static let openAppWhenRun = true

    @Parameter(title: "Mac") var mac: MacEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = ClientModel.shared
        guard !model.paired.isEmpty else { throw ShortcutError(localizedStringResource: "No Mac is paired yet.") }
        model.requestConnect(hostID: mac?.id ?? (model.paired.count == 1 ? model.paired[0].id : nil))
        return .result()
    }
}

struct DisconnectIntent: AppIntent {
    static let title: LocalizedStringResource = "Disconnect from Mac"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ClientModel.shared.disconnect()
        return .result()
    }
}

struct TabletModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Tablet Mode"
    static let description = IntentDescription("Turns the iPad into a pen tablet without a picture, or back.")
    static let openAppWhenRun = true

    @Parameter(title: "Tablet Mode", default: .toggle) var state: Switch

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = ClientModel.shared
        model.settings.tabletMode = state.apply(to: model.settings.tabletMode)
        return .result()
    }
}

struct LaserPointerIntent: AppIntent {
    static let title: LocalizedStringResource = "Laser Pointer"
    static let description = IntentDescription("The Pencil draws fading marks on the Mac screen instead of clicking.")
    static let openAppWhenRun = true

    @Parameter(title: "Laser Pointer", default: .toggle) var state: Switch

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = ClientModel.shared
        model.laserMode = state.apply(to: model.laserMode)
        return .result()
    }
}

struct MacScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Mac Screenshot"
    static let description = IntentDescription("Takes what is streamed at the Mac's full resolution and opens it for cropping and saving.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = ClientModel.shared
        guard case .connected = model.phase else { throw ShortcutError(localizedStringResource: "Not connected to a Mac.") }
        model.requestScreenshot()
        return .result()
    }
}

enum ToolChoice: String, AppEnum {
    case ruler, perspective1, perspective2, perspective3, ellipse, shapeRecognition, laser, palette, mirror, grayscale, grid
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tool"
    static let caseDisplayRepresentations: [ToolChoice: DisplayRepresentation] = [
        .ruler: "Ruler", .perspective1: "Perspective (1 point)", .perspective2: "Perspective (2 points)",
        .perspective3: "Perspective (3 points)", .ellipse: "Ellipse template", .shapeRecognition: "Shape recognition",
        .laser: "Laser pointer", .palette: "Palette from the Mac", .mirror: "Mirror view", .grayscale: "Grayscale preview", .grid: "Grid",
    ]
    var tool: IPadTool { IPadTool(rawValue: rawValue) ?? .ruler }
}

struct ToggleToolIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle iPad Tool"
    static let description = IntentDescription("Shows or hides a drawing aid, or switches a tool on or off.")
    static let openAppWhenRun = true

    @Parameter(title: "Tool", default: .ruler) var tool: ToolChoice

    @MainActor
    func perform() async throws -> some IntentResult {
        ClientModel.shared.runTool(tool.tool)
        return .result()
    }
}

struct UniversePenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectToMacIntent(), phrases: [
            "Connect \(.applicationName)",
            "Connect \(.applicationName) to my Mac",
        ], shortTitle: "Connect to Mac", systemImageName: "macbook.and.ipad")
        AppShortcut(intent: TabletModeIntent(), phrases: [
            "Toggle tablet mode in \(.applicationName)",
        ], shortTitle: "Tablet Mode", systemImageName: "rectangle.dashed")
        AppShortcut(intent: LaserPointerIntent(), phrases: [
            "Toggle the laser pointer in \(.applicationName)",
        ], shortTitle: "Laser Pointer", systemImageName: "light.max")
        AppShortcut(intent: MacScreenshotIntent(), phrases: [
            "Take a Mac screenshot with \(.applicationName)",
        ], shortTitle: "Mac Screenshot", systemImageName: "camera.viewfinder")
        AppShortcut(intent: ToggleToolIntent(), phrases: [
            "Toggle a tool in \(.applicationName)",
        ], shortTitle: "Toggle iPad Tool", systemImageName: "ruler")
        AppShortcut(intent: DisconnectIntent(), phrases: [
            "Disconnect \(.applicationName)",
        ], shortTitle: "Disconnect", systemImageName: "xmark.circle")
    }
}
