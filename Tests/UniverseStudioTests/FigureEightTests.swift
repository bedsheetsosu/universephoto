import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FigureEightTests {
    @Test func crossesItsStartAndLoops() {
        let p = (0...16).map { Studio.figureEightOffset($0, of: 16, radius: 50) }
        #expect(abs(p[0].0) < 1e-9 && abs(p[0].1) < 1e-9)
        #expect(abs(p[8].0) < 1e-9 && abs(p[8].1) < 1e-9)      // through the middle again
        #expect(abs(p[16].0) < 1e-9 && abs(p[16].1) < 1e-9)
        #expect(p[4].0 > 40 && p[12].0 < -40)                     // both loops
    }
}
