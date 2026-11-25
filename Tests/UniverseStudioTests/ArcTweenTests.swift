import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct ArcTweenTests {
    @Test func arcBulgesOffTheStraightLine() {
        // Horizontal move: an arc should push the middle in-between off the line (non-zero y).
        var a = ArtLayer(name: "ball"); a.transform = LayerTransform(x: 0, y: 0, scale: 1, rotation: 0)
        var b = a; b.transform = LayerTransform(x: 100, y: 0, scale: 1, rotation: 0)
        let straight = Tween.frames(from: [a], to: [b], count: 3, curve: .linear, arc: 0)
        let arced = Tween.frames(from: [a], to: [b], count: 3, curve: .linear, arc: 0.3)
        #expect(straight.allSatisfy { abs($0[0].transform.y) < 1e-9 })      // straight stays on the line
        #expect(abs(arced[1][0].transform.y) > 1)                           // arced middle lifts off it
        // x still runs end to end.
        #expect(abs(arced[0][0].transform.x - 25) < 1e-9 && abs(arced[2][0].transform.x - 75) < 1e-9)
    }

    @Test func arcSignFlipsTheSide() {
        let a = ArtLayer(name: "ball")
        var b = a; b.transform.x = 100
        let up = Tween.frames(from: [a], to: [b], count: 1, curve: .linear, arc: 0.3)[0][0].transform.y
        let down = Tween.frames(from: [a], to: [b], count: 1, curve: .linear, arc: -0.3)[0][0].transform.y
        #expect(up == -down && up != 0)
    }

    @Test func noMoveNoArc() {
        let a = ArtLayer(name: "still")
        let mid = Tween.frames(from: [a], to: [a], count: 2, curve: .linear, arc: 0.5)
        #expect(mid.allSatisfy { $0[0].transform.x == a.transform.x && $0[0].transform.y == a.transform.y })
    }
}
