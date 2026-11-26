import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct BeamLayerTests {
    @Test func squeezesWidthKeepsHeight() {
        let p = Studio.beamPose(0.5)
        let t = LayerTransform(scale: p.scale, stretch: p.stretch)
        #expect(abs(t.scaleY - 1) < 1e-9 && t.scaleX < 0.6)
        #expect(Studio.beamPose(1).opacity == 0 && Studio.beamPose(0).opacity == 1)
    }

    @Test func beamOutEndsInvisibleBeamInStartsInvisible() {
        for out in [true, false] {
            let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            s.newDocument(width: 200, height: 200, background: .white)
            s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 60, pressure: 1), InkPoint(x: 140, y: 160, pressure: 1)], color: .black, width: 8)]
            s.changed(); s.selectedLayer = 1
            s.extendAnimation(by: 11)
            #expect(s.beamLayer(out: out) == 12)
            let f = s.document().frames
            #expect((out ? f.last! : f[0])[1].opacity == 0)
            #expect((out ? f[0] : f.last!)[1].opacity == 1)
        }
    }
}
