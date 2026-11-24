import Testing
@testable import UniverseStudio

@MainActor
struct HSBPickerTests {
    @Test func hsbRoundTrips() {
        let red = HSBPicker.color(h: 0, s: 1, b: 1, alpha: 0.5)
        #expect(red.red > 0.99 && red.green < 0.01 && red.blue < 0.01 && red.alpha == 0.5)
        let c = HSBPicker.color(h: 0.6, s: 0.4, b: 0.7, alpha: 1)
        let (h, s, b) = c.hsb
        #expect(abs(h - 0.6) < 0.01 && abs(s - 0.4) < 0.01 && abs(b - 0.7) < 0.01)
        // Out-of-range drags are clamped.
        let black = HSBPicker.color(h: 2, s: -1, b: -3, alpha: 1)
        #expect(black.red == 0 && black.green == 0 && black.blue == 0)
    }
}
