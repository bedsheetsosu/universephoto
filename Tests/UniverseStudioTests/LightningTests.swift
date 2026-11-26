import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct LightningTests {
    @Test func doubleFlashesNowAndThen() {
        let l = Studio.lightningLevels(count: 72, gap: 24)
        let strikes = l.indices.filter { l[$0] == 0.75 }
        #expect(strikes.count >= 2 && strikes.count <= 4)
        #expect(l[strikes[0] + 2] == 0.6 && l[strikes[0] + 4] == 0)
        #expect(l.first == 0)
    }

    @Test func flashLayerOnTop() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 20, height: 20, background: .white)
        s.fps = 12
        for _ in 0..<35 { s.addFrame() }
        s.selectFrame(0)
        #expect(s.addLightning(everySeconds: 1) >= 2)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.last!.blend == .screen })
        #expect(f.contains { $0.last!.opacity > 0.7 } && f.contains { $0.last!.opacity == 0 })
    }
}
