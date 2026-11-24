import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct DuplicateImageTests {
    @Test func duplicateOpensACopyTab() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 30, height: 12); s.newLayer(); s.layers[1].opacity = 0.4
        let tabs = s.tabs.count, original = s.documentName
        s.duplicateImage()
        #expect(s.tabs.count == tabs + 1)
        #expect(s.width == 30 && s.height == 12 && s.layers.count == 2 && s.layers[1].opacity == 0.4)
        #expect(s.documentName.contains(original) && s.documentName != original)
        #expect(s.tabs.last?.url == nil)
    }

    @Test func pixelGridOnlyWhenZoomedIn() {
        let r = CGRect(x: 2.5, y: 3, width: 4, height: 2)
        #expect(Studio.pixelGridLines(visible: r, width: 10, height: 10, scale: 4) == nil)
        let l = Studio.pixelGridLines(visible: r, width: 10, height: 10, scale: 8)
        #expect(l?.xs == [2, 3, 4, 5, 6, 7] && l?.ys == [3, 4, 5])
        #expect(Studio.pixelGridLines(visible: CGRect(x: -50, y: -50, width: 500, height: 500), width: 10, height: 10, scale: 8)?.xs == Array(0...10))
        #expect(Studio.pixelGridLines(visible: CGRect(x: 0, y: 0, width: 5000, height: 5000), width: 5000, height: 5000, scale: 8) == nil, "too many lines")
    }
}
