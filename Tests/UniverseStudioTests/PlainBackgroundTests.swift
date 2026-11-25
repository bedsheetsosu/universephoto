import Testing
import Foundation
@testable import UniverseStudio

struct PlainBackgroundTests {
    @Test func oldSwitchCountsAsGreyAndNewChoiceWins() throws {
        let name = "plainbg-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        #expect(PhotoTheme.plainStyle(d) == "off")
        d.set(true, forKey: "photoPlainBackground")
        #expect(PhotoTheme.plainStyle(d) == "grey")
        d.set("white", forKey: "photoPlainStyle")
        #expect(PhotoTheme.plainStyle(d) == "white")
        d.set("off", forKey: "photoPlainStyle")
        #expect(PhotoTheme.plainStyle(d) == "off")
    }
}
