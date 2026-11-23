import CoreGraphics
import Testing
@testable import UniversePhoto

@MainActor
struct QuickMaskTests {
    @Test func selectionRoundTripsAndPaintingAdds() throws {
        let s = Studio()
        let layerCount = s.layers.count, active = s.selectedLayer
        s.selection = CanvasSelection(points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)])
        s.enterQuickMask()
        #expect(s.quickMaskActive && s.layers.count == layerCount + 1 && s.selection == nil && s.activeLayer?.opacity == 0.5)
        // A painted dab elsewhere (as the brush would add it) joins the selection.
        var dab = InkStroke(points: [InkPoint(x: 400, y: 400, pressure: 1), InkPoint(x: 420, y: 400, pressure: 1)], color: Studio.quickMaskRed, width: 20)
        dab.color.alpha = 1
        s.add(dab)
        s.exitQuickMask()
        #expect(!s.quickMaskActive && s.layers.count == layerCount && s.selectedLayer == active)
        let mask = try #require(s.selectionMask())
        func at(_ x: Int, _ y: Int) -> UInt8 { mask[y * s.width + x] }
        #expect(at(150, 150) > 200 && at(410, 400) > 200 && at(300, 300) == 0)
    }

    @Test func emptyQuickMaskMeansNoSelection() {
        let s = Studio()
        s.enterQuickMask()
        s.exitQuickMask()
        #expect(s.selection == nil && !s.quickMaskActive)
    }
}
