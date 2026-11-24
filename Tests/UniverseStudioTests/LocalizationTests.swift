import XCTest
import Combine
@testable import UniverseStudio

final class LocalizationTests: XCTestCase {
    func testCatalogHasCompleteEnglishGermanTranslations() throws {
        let catalog = LocalizedText.catalog
        XCTAssertFalse(catalog.isEmpty, "The packaged translation catalog must be readable in SwiftPM and the app bundle")
        for (key, translations) in catalog {
            XCTAssertEqual(Set(translations.keys), Set(["en", "de"]), "Incomplete language coverage for \(key)")
            XCTAssertEqual(translations["en"], key, "English source keys must remain the default copy")
            XCTAssertFalse(try XCTUnwrap(translations["de"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty German translation: \(key)")
        }
        let mediaKeys = [
            "This format is not supported:",
            "The image file is invalid or could not be decoded.",
            "Images support 1–8192 pixels per side and up to 64 million pixels. MP4 requires even dimensions.",
            "The destination file already exists. Choose a different name.",
            "Export failed:",
            "At least one frame is required for export.",
            "H.264 is not available on this system",
            "MP4 timeout"
        ]
        for key in mediaKeys { XCTAssertNotNil(catalog[key]?["de"], "Missing media error translation: \(key)") }
    }

    func testMissingAndUnsupportedPreferencesDefaultToEnglish() {
        for stored in [nil, "", "fr", "DE", "automatic"] {
            XCTAssertEqual(LocalizedText.normalizedLanguage(stored), "en")
        }
        XCTAssertEqual(LocalizedText.normalizedLanguage("de"), "de")
        let source = "At least one frame is required for export."
        XCTAssertEqual(LocalizedText.string(source, language: "en"), source)
        XCTAssertEqual(LocalizedText.string(source, language: "fr"), source)
        XCTAssertEqual(LocalizedText.string("A user-provided filename.psd", language: "de"), "A user-provided filename.psd")
    }

    @MainActor func testLanguageChangePublishesImmediatelyAndPersists() {
        withRestoredPreferences {
            let localization = Localization.shared
            localization.language = "en"
            var published: [String] = []
            let subscription = localization.$language.dropFirst().sink { published.append($0) }
            localization.language = "de"
            XCTAssertEqual(localization.language, "de")
            XCTAssertEqual(UserDefaults.standard.string(forKey: "language"), "de")
            XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "AppleLanguages"), ["de"])
            XCTAssertEqual(LocalizedText.language, "de")
            XCTAssertEqual(LocalizedText.string("At least one frame is required for export."), "Für den Export wird mindestens ein Frame benötigt.")
            localization.language = "en"
            XCTAssertEqual(UserDefaults.standard.string(forKey: "language"), "en")
            XCTAssertEqual(published, ["de", "en"])
            withExtendedLifetime(subscription) {}
        }
    }

    @MainActor func testCapturedMediaErrorUsesCurrentLanguageAndKeepsItsDetails() {
        withRestoredPreferences {
            let error = ImageFiles.FileError.encoder("H.264 is not available on this system")
            Localization.shared.language = "en"
            XCTAssertEqual(error.errorDescription, "Export failed: H.264 is not available on this system")
            Localization.shared.language = "de"
            XCTAssertEqual(error.errorDescription, "Der Export ist fehlgeschlagen: H.264 ist auf diesem System nicht verfügbar")
            XCTAssertEqual(ImageFiles.FileError.unsupported("psd").errorDescription, "Dieses Format wird nicht unterstützt: psd")
            Localization.shared.language = "en"
            XCTAssertEqual(error.errorDescription, "Export failed: H.264 is not available on this system")
        }
    }

    func testTranslationLookupWorksOffMainThread() async {
        let translation = await Task.detached {
            LocalizedText.string("At least one frame is required for export.", language: "de")
        }.value
        XCTAssertEqual(translation, "Für den Export wird mindestens ein Frame benötigt.")
    }

    @MainActor private func withRestoredPreferences(_ body: () -> Void) {
        let language = UserDefaults.standard.object(forKey: "language")
        let nativeLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
        let current = Localization.shared.language
        defer {
            Localization.shared.language = current
            if let language { UserDefaults.standard.set(language, forKey: "language") }
            else { UserDefaults.standard.removeObject(forKey: "language") }
            if let nativeLanguages { UserDefaults.standard.set(nativeLanguages, forKey: "AppleLanguages") }
            else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        }
        body()
    }
}
