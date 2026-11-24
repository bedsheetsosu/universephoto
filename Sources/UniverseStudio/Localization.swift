import Foundation
import Combine
import AppKit

/// The xcstrings file is the single translation source. It is copied as a resource so
/// both SwiftPM and the standalone app use the same catalog without an Xcode-only build step.
enum LocalizedText {
    static let supportedLanguages = ["en", "de"]
    static var language: String { normalizedLanguage(UserDefaults.standard.string(forKey:"language")) }
    static func normalizedLanguage(_ stored:String?) -> String { supportedLanguages.contains(stored ?? "") ? stored! : "en" }
    static var locale:Locale { Locale(identifier:language) }
    static let catalog:[String:[String:String]] = {
        guard let url = Bundle.module.url(forResource:"Localizable",withExtension:"xcstrings"),
              let data = try? Data(contentsOf:url),let root = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let strings = root["strings"] as? [String:[String:Any]] else { preconditionFailure("Missing localization catalog") }
        var result:[String:[String:String]] = [:]
        for (key,entry) in strings {
            guard let localizations = entry["localizations"] as? [String:[String:Any]] else { continue }
            var values:[String:String] = [:]
            for (language,value) in localizations { if let unit = value["stringUnit"] as? [String:String],let text = unit["value"] { values[language] = text } }
            result[key] = values
        }
        return result
    }()
    static func string(_ key:String,language:String? = nil)->String { catalog[key]?[normalizedLanguage(language ?? Self.language)] ?? catalog[key]?["en"] ?? key }
    static func format(_ key:String,_ arguments:[CVarArg],language:String? = nil)->String { String(format:string(key,language:language),locale:Locale(identifier:normalizedLanguage(language ?? Self.language)),arguments:arguments) }
    static func errorDescription(_ error:Error)->String {
        if let error = error as? StudioError { return error.localizedDescription }
        // Keep the renderer unchanged; translate its user-facing failure at the boundary.
        if error is Renderer.RenderError { return string("The image could not be encoded.") }
        if let error = error as? ImageFiles.FileError { return error.errorDescription ?? string("The operation could not be completed.") }
        if error is DecodingError { return string("This file is not a valid UniverseStudio document.") }
        if let error = error as? CocoaError {
            switch error.code { case .fileReadNoSuchFile: return string("The file could not be found.")
            case .fileReadNoPermission,.fileWriteNoPermission:return string("Permission to access this file was denied.")
            case .fileWriteOutOfSpace:return string("There is not enough free space to save this file.")
            default:return string("The file could not be read or written.") }
        }
        let value = error.localizedDescription
        // Our media and protocol errors already read the catalog at access time.
        if catalog.values.contains(where:{ $0.values.contains(value) }) { return value }
        return string("The operation could not be completed.")
    }
}
@MainActor final class Localization:ObservableObject {
    static let shared = Localization()
    @Published var language:String {
        didSet { let normalized = LocalizedText.normalizedLanguage(language);if normalized != language { language = normalized };UserDefaults.standard.set(language,forKey:"language");configureNativeLanguage();Task { @MainActor in self.refreshNativeMenus() } }
    }
    private init() { language = LocalizedText.language;configureNativeLanguage() }
    func configureNativeLanguage() { UserDefaults.standard.set([language],forKey:"AppleLanguages") }
    func refreshNativeMenus() {
        guard let menu = NSApp?.mainMenu else { return }
        func translate(_ menu:NSMenu) {
            for item in menu.items {
                let key = LocalizedText.catalog[item.title] != nil ? item.title : LocalizedText.catalog.first(where:{ $0.value["de"] == item.title || $0.value["en"] == item.title })?.key
                if let key { item.title = LocalizedText.string(key) }
                if let submenu = item.submenu { translate(submenu) }
            }
        }
        translate(menu)
    }
}
func L(_ key:String)->String { LocalizedText.string(key) }
func LF(_ key:String,_ arguments:CVarArg...)->String { LocalizedText.format(key,arguments) }

func LC(_ singular:String,_ plural:String,_ count:Int)->String { LocalizedText.format(count == 1 ? singular : plural,[count]) }
