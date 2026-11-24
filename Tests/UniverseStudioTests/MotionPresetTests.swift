import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct MotionPresetTests {
    @Test func curvesStartAndEndRight() {
        for p in MotionPreset.allCases {
            let a = p.pose(0, w: 100, h: 100)
            if p == .slideIn { #expect(a.dx == -100) }
            else if p == .fadeIn { #expect(a.alpha == 0) }
            else if p == .pop { #expect(a.scale < 0.01) }
            else if p == .dropIn { #expect(a.dy == -60) }
            else { #expect(abs(a.dx) < 1e-9 && abs(a.dy) < 1e-9 && abs(a.rot) < 1e-9 && abs(a.scale - 1) < 1e-9 && a.alpha == 1, "\(p) starts at rest") }
            if !p.loops && p != .slideOut && p != .fadeOut {
                let e = p.pose(1, w: 100, h: 100)
                #expect(abs(e.dx) < 1e-9 && abs(e.dy) < 1e-9 && abs(e.scale - 1) < 1e-9 && e.alpha == 1, "\(p) ends at rest")
            }
            let names = Set(MotionPreset.allCases.map(\.title)); #expect(names.count == MotionPreset.allCases.count)
        }
        #expect(MotionPreset.spin.steps(4) == [0, 0.25, 0.5, 0.75] && MotionPreset.fadeIn.steps(3) == [0, 0.5, 1])
    }

    @Test func oneFrameBecomesAMovement() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100); s.newLayer(); s.layers[1].transform.x = 10
        #expect(s.applyMotionPreset(.spin, count: 4) == 4)
        let d = s.document()
        #expect(d.frames.map { $0[1].transform.rotation } == [0, 90, 180, 270])
        #expect(d.frames.allSatisfy { $0[1].transform.x == 10 && $0[0].transform == LayerTransform() })
        s.undo(); #expect(s.document().frames.count <= 1)
        s.selectFrame(0)
        #expect(s.applyMotionPreset(.fadeOut, count: 3) == 3)
        #expect(s.document().frames.map { $0[1].opacity } == [1, 0.5, 0])
    }
}
