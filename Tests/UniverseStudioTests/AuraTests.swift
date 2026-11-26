import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct AuraTests {
    @Test func darkBrushGlowsGold() {
        #expect(Studio.glowColour(.black).red == 1)
        let blue = CodableColor(red: 0.2, green: 0.5, blue: 1, alpha: 1)
        #expect(Studio.glowColour(blue).blue == 1)
    }

    @Test func pulsesBehindTheLayer() {
        let b = CGRect(x: 50, y: 50, width: 100, height: 100)
        let big = Studio.auraStrokes(around: b, pulse: 1, colour: .black), small = Studio.auraStrokes(around: b, pulse: -1, colour: .black)
        #expect(big.count == 9)
        #expect(big[0].points[0].x < small[0].points[0].x)
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 60, pressure: 1), InkPoint(x: 140, y: 160, pressure: 1)], color: .black, width: 8)]
        let id = s.layers[1].id
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 11)
        #expect(s.addAura() == 12)
        #expect(s.document().frames.allSatisfy { $0.count == 3 && $0[1].name == L("Aura") && $0[2].id == id })
    }
}
