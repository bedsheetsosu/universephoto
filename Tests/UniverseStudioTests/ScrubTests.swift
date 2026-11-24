import Testing
@testable import UniverseStudio

struct ScrubTests {
    @Test func fractionToFrameWithHolds() {
        let holds = [1, 3, 1]          // 5 ticks
        #expect(Scrub.frame(at: 0, holds: holds) == 0)
        #expect(Scrub.frame(at: 0.25, holds: holds) == 1)
        #expect(Scrub.frame(at: 0.7, holds: holds) == 1)
        #expect(Scrub.frame(at: 0.85, holds: holds) == 2)
        #expect(Scrub.frame(at: 5, holds: holds) == 2 && Scrub.frame(at: -1, holds: holds) == 0)
        #expect(Scrub.span(of: 1, holds: holds) == (0.2, 0.8))
    }
}
