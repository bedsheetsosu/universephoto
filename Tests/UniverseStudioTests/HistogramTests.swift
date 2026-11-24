import Testing
import SwiftUI
@testable import UniverseStudio

struct HistogramTests {
    @Test func statsOfASimpleSpread() {
        var c = [Double](repeating: 0, count: 256); c[10] = 2; c[20] = 2
        let s = HistogramStats(c)
        #expect(s.pixels == 4 && s.mean == 15 && s.deviation == 5 && s.median == 10)
        #expect(HistogramStats([Double](repeating: 0, count: 256)) == HistogramStats([]))
    }

    @Test func channelsPickTheRightCurves() {
        #expect(HistogramChannel.colors.indices == [0, 1, 2] && HistogramChannel.colors.statsIndex == 3)
        #expect(HistogramChannel.blue.statsIndex == 2 && HistogramChannel.luminosity.indices == [3])
    }

    @Test func pathFitsTheBox() {
        var c = [Double](repeating: 0, count: 256); c[128] = 50
        let b = HistogramPanel.path(c, in: CGSize(width: 100, height: 40), peak: 25).boundingRect
        #expect(b.minX == 0 && b.maxX == 100 && b.minY == 0 && b.maxY == 40, "spikes are capped at the top")
        #expect(HistogramPanel.path(c, in: CGSize(width: 100, height: 40), peak: 0).isEmpty)
    }
}

struct HistogramPeakTests {
    @Test func flatColourStillShowsAndCountsScaleUp() {
        var c = [Double](repeating: 0, count: 256); c[255] = 900
        #expect(HistogramPanel.peak([c]) == 900)
        var spread = [Double](repeating: 10, count: 256); spread[0] = 5000
        #expect(HistogramPanel.peak([spread]) == 10)
        #expect(HistogramPanel.sampleScale(width: 1200, height: 800) == 1200.0 * 800 / (512 * 341))
        #expect(HistogramPanel.sampleScale(width: 300, height: 200) == 1)
    }
}
