import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct StaggerTests {
    @Test func progressAndLayers() {
        #expect(Stagger.progress(frame: 0, entrant: 1, gap: 2, duration: 4) < 0)
        #expect(Stagger.progress(frame: 4, entrant: 1, gap: 2, duration: 4) == 0.5)
        #expect(Stagger.progress(frame: 20, entrant: 1, gap: 2, duration: 4) == 1)
        var bg = ArtLayer(name: "BG"); bg.visible = true
        var shared = ArtLayer(name: "S"); shared.allFrames = true
        let a = ArtLayer(name: "A"), b = ArtLayer(name: "B")
        #expect(Stagger.movingLayers([bg, a, shared, b]) == [a.id, b.id])
    }

    @Test func layersComeInOneByOne() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.newLayer()
        #expect(s.layers.count == 3)
        #expect(s.staggerIn(.fadeIn, gap: 2, duration: 4, restTicks: 5) == 7)
        let f = s.document().frames
        #expect(f[0][1].opacity == 0 && f[0][2].opacity == 0 && f[0][0].opacity == 1)
        #expect(f[2][1].opacity > 0 && f[2][2].opacity == 0)
        #expect(f[6][1].opacity == 1 && f[6][2].opacity == 1 && s.hold(6) == 5)
    }
}
