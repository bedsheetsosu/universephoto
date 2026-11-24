import Foundation
import Combine

/// In-app language, independent of the system language and switchable without restart.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, de, es, ja, zh, ko, hi

    /// Language code the system uses for its own UI (lproj name).
    public var systemCode: String { self == .zh ? "zh-Hans" : rawValue }

    public var id: String { rawValue }
    /// Name in its own language (shown in the picker regardless of the current language).
    public var nativeName: String {
        switch self {
        case .en: return "English"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .ja: return "日本語"
        case .zh: return "中文（简体）"
        case .ko: return "한국어"
        case .hi: return "हिन्दी"
        }
    }
    public var flag: String {
        switch self {
        case .en: return "🇬🇧"
        case .de: return "🇩🇪"
        case .es: return "🇪🇸"
        case .ja: return "🇯🇵"
        case .zh: return "🇨🇳"
        case .ko: return "🇰🇷"
        case .hi: return "🇮🇳"
        }
    }
}

/// Localisation store. Keys are the German UI texts (the code was written in German); each other
/// language has a table in `Translations.swift`. Missing entries fall back to the key, and
/// `Tools/check-l10n.py` lists keys that have no English entry.
public final class L10n: ObservableObject, @unchecked Sendable {
    public static let shared = L10n()
    private static let defaultsKey = "appLanguage"

    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            Self.applySystemLanguage(language)
        }
    }

    /// System-drawn UI (share sheet, file picker, Delete/Cancel/Done, context menus) follows the
    /// app's language list, not our tables. Setting it per app takes effect at the next launch.
    private static func applySystemLanguage(_ l: AppLanguage) {
        UserDefaults.standard.set([l.systemCode], forKey: "AppleLanguages")
    }

    /// Whether the user has picked a language yet (first-run setup starts with that).
    public var hasChosen: Bool { UserDefaults.standard.string(forKey: Self.defaultsKey) != nil }

    private init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "") ?? .en
        if hasChosen { Self.applySystemLanguage(language) }
    }

    /// A key in all languages (e.g. to recognise a window title whatever language it was opened in).
    public static func allTranslations(of key: String) -> Set<String> {
        Set(AppLanguage.allCases.map { $0 == .de ? key : (Translations.table(for: $0)[key] ?? key) })
    }

    public func string(_ key: String) -> String {
        if language == .de { return key }
        // Missing entries fall back to English, then to the German key.
        return Translations.table(for: language)[key] ?? Translations.en[key] ?? key
    }
}

/// Localised text for a German key. With arguments the key is a format string (`%@`, `%d`, …).
public func L(_ key: String, _ args: CVarArg...) -> String {
    let s = L10n.shared.string(key)
    return args.isEmpty ? s : String(format: s, arguments: args)
}

/// Display form of a link description from `TafelNetwork.describe` ("USB-Kabel (en8)", "WLAN (en0)", …).
/// The raw string stays German because code checks it (`hasPrefix("USB")`); only the shown text is
/// translated.
public func localizedLink(_ s: String) -> String {
    guard L10n.shared.language != .de else { return s }
    var r = s
    // Longest first: "Peer-to-Peer-WLAN" contains "WLAN".
    for (de, shown) in [("USB-Kabel", L("USB-Kabel")), ("Peer-to-Peer-WLAN", L("Peer-to-Peer-WLAN")), ("WLAN", L("WLAN")),
                        ("Mobilfunk", L("Mobilfunk")), ("Sonstige", L("Sonstige"))] {
        r = r.replacingOccurrences(of: de, with: shown)
    }
    return r
}
