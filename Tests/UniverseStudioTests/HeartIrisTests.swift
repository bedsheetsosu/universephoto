import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct HeartIrisTests {
    @Test func heartCoversTheCornersWhenBig() {
        for (w, h) in [(200.0, 150.0), (150.0, 200.0), (100.0, 400.0), (400.0, 100.0)] {
            let full = (w * w + h * h).squareRoot() / 2, f = Studio.heartCoverFactor(width: w, height: h)
            #expect(f < 12)
            let path = CGMutablePath()
            path.addLines(between: Studio.heartOutline(cx: w / 2, cy: h / 2, rad: full * 0.999, factor: f)); path.closeSubpath()
            for c in [CGPoint(x: 1, y: 1), CGPoint(x: w - 1, y: 1), CGPoint(x: 1, y: h - 1), CGPoint(x: w - 1, y: h - 1), CGPoint(x: w / 2, y: 1)] {
                #expect(path.contains(c))
            }
        }
    }

    @Test func heartCloseMasksWithAHeart() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.extendAnimation(by: 9)
        s.selectedLayer = 0
        #expect(s.irisLayer(open: false, heart: true) > 0)
        let m = s.document().frames[5][0].mask ?? []
        #expect(m.contains { $0.kind == "path" && $0.pathClosed == true })
    }
}
