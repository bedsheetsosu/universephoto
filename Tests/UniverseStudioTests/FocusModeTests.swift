import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FocusModeTests {
    @Test func startsOffAndThemeFollowsAppearance() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(!s.focusMode)
        #expect(FocusMode.theme(appearance: "dark", accent: "mint", systemDark: false).isDark)
        #expect(!FocusMode.theme(appearance: "light", accent: "mint", systemDark: true).isDark)
        #expect(FocusMode.theme(appearance: "system", accent: "rose", systemDark: true).isDark)
    }
}
