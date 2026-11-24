import Foundation

/// One-time move from the old UniversePhoto app (bundle `local.universephoto`) to UniverseStudio:
/// settings and recovery copies come along, the old files stay where they were.
enum AppMigration {
    static let bundleID = "local.universestudio"
    static let legacyBundleID = "local.universephoto"
    static let supportFolder = "UniverseStudio"
    static let legacySupportFolder = "UniversePhoto"
    static let doneKey = "migratedFromUniversePhoto"

    /// Copies keys from the old preference domain that the new one does not have yet. Returns how many.
    @discardableResult
    static func migrateDefaults(from old: [String: Any]?, into defaults: UserDefaults) -> Int {
        guard !defaults.bool(forKey: doneKey) else { return 0 }
        var copied = 0
        for (key, value) in old ?? [:] where defaults.object(forKey: key) == nil && !key.hasPrefix("NS") && key != "AppleLanguages" {
            defaults.set(value, forKey: key); copied += 1
        }
        defaults.set(true, forKey: doneKey)
        return copied
    }

    /// Copies recovery files from the old support folder when the new one has none.
    @discardableResult
    static func migrateRecovery(supportRoot: URL, fileManager fm: FileManager = .default) -> Int {
        let old = supportRoot.appendingPathComponent(legacySupportFolder + "/Recovery", isDirectory: true)
        let new = supportRoot.appendingPathComponent(supportFolder + "/Recovery", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil), !files.isEmpty else { return 0 }
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        var copied = 0
        for f in files where !fm.fileExists(atPath: new.appendingPathComponent(f.lastPathComponent).path) {
            if (try? fm.copyItem(at: f, to: new.appendingPathComponent(f.lastPathComponent))) != nil { copied += 1 }
        }
        return copied
    }

    /// Runs both steps for the real app; call before any preference is read.
    static func run() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: doneKey) else { return }
        migrateDefaults(from: d.persistentDomain(forName: legacyBundleID), into: d)
        if let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first { migrateRecovery(supportRoot: root) }
    }
}
