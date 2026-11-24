import XCTest
@testable import UniverseStudio

final class AppMigrationTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "UniverseStudioTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name); return d
    }

    func testCopiesOldSettingsOnceWithoutOverwriting() {
        let d = freshDefaults()
        d.set("dark", forKey: "appearance")
        let old: [String: Any] = ["photoAccent": "rose", "appearance": "light", "NSWindow Frame x": "1", "AppleLanguages": ["xx-test"]]
        XCTAssertEqual(AppMigration.migrateDefaults(from: old, into: d), 1)
        XCTAssertEqual(d.string(forKey: "photoAccent"), "rose")
        XCTAssertEqual(d.string(forKey: "appearance"), "dark", "new values win")
        XCTAssertNil(d.object(forKey: "NSWindow Frame x"))
        XCTAssertNotEqual(d.stringArray(forKey: "AppleLanguages"), ["xx-test"], "AppleLanguages is not copied")
        XCTAssertEqual(AppMigration.migrateDefaults(from: ["swatches": "x"], into: d), 0, "runs only once")
    }

    func testCopiesRecoveryFilesAndKeepsOldOnes() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("UniverseStudio-Migration-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("UniversePhoto/Recovery"), new = root.appendingPathComponent("UniverseStudio/Recovery")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: old.appendingPathComponent("a.universephoto"))
        try Data("b".utf8).write(to: old.appendingPathComponent("b.universephoto"))
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: new.appendingPathComponent("b.universephoto"))
        XCTAssertEqual(AppMigration.migrateRecovery(supportRoot: root), 1)
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("b.universephoto"), encoding: .utf8), "new")
        XCTAssertTrue(fm.fileExists(atPath: old.appendingPathComponent("a.universephoto").path), "old copies stay")
        XCTAssertEqual(AppMigration.migrateRecovery(supportRoot: root.appendingPathComponent("missing")), 0)
    }

    @MainActor func testStartScreenAndModuleSwitch() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UniverseStudio-Module-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = Studio(recoveryRoot: dir)
        s.module = nil
        s.enter(.photo); XCTAssertEqual(s.module, .photo)
        s.showStartScreen(); XCTAssertNil(s.module)
        let url = dir.appendingPathComponent("Doc.universephoto")
        try s.save(to: url)
        s.showStartScreen()
        try s.open(url)
        XCTAssertEqual(s.module, .photo, "opening a file enters the photo module")
        XCTAssertEqual(AppMigration.bundleID, "local.universestudio")
        XCTAssertEqual(UniversePenAdapter.bundleID, AppMigration.bundleID)
    }
}
