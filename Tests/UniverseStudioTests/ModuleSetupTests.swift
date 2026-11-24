import Testing
import Foundation
@testable import UniverseStudio
import UniversePenHost

@MainActor
struct ModuleSetupTests {
    @Test func enabledModulesParseAndStore() {
        #expect(ModuleSettings.enabled(nil) == [.photo])
        #expect(ModuleSettings.enabled("pen,photo") == [.photo, .pen])
        #expect(ModuleSettings.enabled("pen,video") == [.pen])
        #expect(ModuleSettings.store([.pen, .photo]) == "photo,pen")
    }

    @Test func setupHasOneStepPerChosenModule() {
        #expect(FirstRunSetup.steps(for: [.photo]) == [.welcome, .modules, .photo, .done])
        #expect(FirstRunSetup.steps(for: [.pen]) == [.welcome, .modules, .pen, .done])
        #expect(FirstRunSetup.steps(for: [.photo, .pen]) == [.welcome, .modules, .photo, .pen, .done])
        #expect(FirstRunSetup.steps(for: []) == [.welcome, .modules, .done])
    }

    @Test func universePenSettingsComeOverOnce() throws {
        let name = "UniverseStudioTests-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name)); defer { d.removePersistentDomain(forName: name) }
        d.set("dark", forKey: "captureMode")
        let old: [String: Any] = ["hostID": "ABC", "captureMode": "region", "debugHostOnboardingStep": 3, "NSWindow Frame main": "x"]
        #expect(UniversePenModule.migrateDefaults(into: d, from: [old]) == 1)
        #expect(d.string(forKey: "hostID") == "ABC", "the iPad knows the Mac by this ID")
        #expect(d.string(forKey: "captureMode") == "dark", "newer values win")
        #expect(d.object(forKey: "debugHostOnboardingStep") == nil && d.object(forKey: "NSWindow Frame main") == nil)
        #expect(UniversePenModule.migrateDefaults(into: d, from: [["enabledPlugins": ["x"]]]) == 0)
    }

    @Test func penModuleIsListed() {
        #expect(StudioModule.allCases == [.photo, .pen])
        #expect(StudioModule.pen.title == "UniversePen")
    }
}
