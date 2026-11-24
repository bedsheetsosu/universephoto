import Testing
import Foundation
@testable import UniverseStudio
import UniversePenHost

@MainActor
struct ModuleSetupTests {
    @Test func enabledModulesParseAndStore() {
        #expect(ModuleSettings.enabled(nil) == [.photo, .animate])
        #expect(ModuleSettings.enabled("pen,photo") == [.photo, .animate, .pen])
        #expect(ModuleSettings.enabled("pen,video") == [.pen])
        #expect(ModuleSettings.store([.pen, .photo]) == "photo,pen,!animate")
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
        #expect(StudioModule.allCases == [.photo, .animate, .pen])
        #expect(StudioModule.pen.title == "UniversePen")
    }
}

@MainActor
struct NavigatorTests {
    @Test func centringPutsThePointInTheMiddle() {
        let s = Studio()
        let v = CGSize(width: 900, height: 600)
        s.zoom = 3; s.rotation = 30
        s.centerView(on: CGPoint(x: 200, y: 150), viewSize: v)
        let mid = CGPoint(x: 200, y: 150).applying(s.geometry(viewSize: v).transform)
        #expect(abs(mid.x - 450) < 0.001 && abs(mid.y - 300) < 0.001)
        // The visible quad is centred on that point too.
        let q = s.visibleQuad(viewSize: v)
        let c = CGPoint(x: q.map(\.x).reduce(0, +) / 4, y: q.map(\.y).reduce(0, +) / 4)
        #expect(abs(c.x - 200) < 0.001 && abs(c.y - 150) < 0.001)
    }

    @Test func fittedViewShowsTheWholeDocument() {
        let s = Studio()
        s.zoom = 1; s.pan = .zero; s.rotation = 0
        let q = s.visibleQuad(viewSize: CGSize(width: 1272, height: 872))
        #expect(q[0].x <= 0 && q[0].y <= 0 && q[2].x >= Double(s.width) && q[2].y >= Double(s.height))
    }
}
