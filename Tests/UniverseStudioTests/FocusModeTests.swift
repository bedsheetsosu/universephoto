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

struct CheckerboardTests {
    @Test func cachedBoardHasTwoGreysInSixteenPixelSquares() throws {
        let img = try #require(Renderer.checkerboard(width: 40, height: 20))
        let b = try #require(PixelOps.bitmap(img))
        func grey(_ x: Int, _ y: Int) -> UInt8 { b.bytes[(y * 40 + x) * 4] }
        #expect(img.width == 40 && img.height == 20)
        #expect(grey(2, 2) != grey(18, 2), "neighbouring squares differ")
        #expect(grey(2, 2) == grey(34, 2), "every other square matches")
        #expect(Renderer.checkerboard(width: 0, height: 5) == nil)
    }
}
