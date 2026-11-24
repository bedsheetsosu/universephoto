import Testing
@testable import UniverseStudio

struct TimelineLayoutTests {
    @Test func holdsBecomeLengthOnlyWhenAsked() {
        #expect(TimelineLayout.cellWidth(hold: 3, zoom: 1, exposure: false) == 82)
        #expect(TimelineLayout.cellWidth(hold: 1, zoom: 1, exposure: true) == 82)
        #expect(abs(TimelineLayout.cellWidth(hold: 3, zoom: 1, exposure: true) - 82 * 1.9) < 1e-9)
        #expect(TimelineLayout.cellWidth(hold: 50, zoom: 1, exposure: true) == 82 * 4, "capped")
        #expect(TimelineLayout.cellWidth(hold: 1, zoom: 1.5, exposure: true) == 123)
    }
}
