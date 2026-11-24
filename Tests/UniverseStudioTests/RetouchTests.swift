import XCTest
import CoreGraphics
@testable import UniverseStudio

@MainActor final class RetouchTests: XCTestCase {
    private let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1), blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)

    private func studio(_ w: Int = 40, _ h: Int = 20) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: w, height: h)
        return s
    }
    private func fill(_ s: Studio, _ rect: CGRect, _ color: CodableColor) {
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: color, width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: rect.minX, y: rect.minY, pressure: 1), InkPoint(x: rect.maxX, y: rect.maxY, pressure: 1)]
        s.add(f)
    }
    private func dab(_ kind: String, at p: CGPoint, width: Double = 10, strength: Double? = nil) -> InkStroke {
        var st = InkStroke(points: [InkPoint(x: p.x, y: p.y, pressure: 1), InkPoint(x: p.x + 1, y: p.y, pressure: 1)], color: .black, width: width)
        st.kind = kind; st.strength = strength
        return st
    }
    private func pixel(_ s: Studio, _ p: CGPoint) throws -> CodableColor {
        Renderer.sample(try XCTUnwrap(Renderer.render(layers: s.layers, width: s.width, height: s.height)), at: p)
    }

    func testCloneStampCopiesFromTheSource() throws {
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 20, height: 20), red); fill(s, CGRect(x: 20, y: 0, width: 20, height: 20), blue)
        XCTAssertFalse(s.beginClone(id: UUID(), at: CGPoint(x: 30, y: 10)), "No source yet")
        s.setCloneSource(CGPoint(x: 10, y: 10))                 // red side
        let stroke = dab("clone", at: CGPoint(x: 30, y: 10))
        XCTAssertTrue(s.beginClone(id: stroke.id, at: CGPoint(x: 30, y: 10)))
        s.add(stroke)
        XCTAssertEqual(s.layers[0].strokes.last?.kind, "bitmap", "Baked into a bitmap stroke")
        XCTAssertNil(Renderer.transient[stroke.id], "The live picture is dropped")
        XCTAssertGreaterThan(try pixel(s, CGPoint(x: 30, y: 10)).red, 0.9, "Red stamped onto blue")
        XCTAssertGreaterThan(try pixel(s, CGPoint(x: 38, y: 2)).blue, 0.9, "Outside the brush stays blue")
    }

    func testAlignedCloneKeepsItsOffset() {
        let s = studio()
        s.setCloneSource(CGPoint(x: 5, y: 5))
        _ = s.beginClone(id: UUID(), at: CGPoint(x: 25, y: 5))
        _ = s.beginClone(id: UUID(), at: CGPoint(x: 30, y: 8))
        XCTAssertEqual(s.cloneSourceMarker(for: CGPoint(x: 30, y: 8)), CGPoint(x: 10, y: 8))
        s.cloneAligned = false
        _ = s.beginClone(id: UUID(), at: CGPoint(x: 30, y: 8))
        XCTAssertEqual(s.cloneOffset, CGSize(width: -25, height: -3), "Not aligned: every stroke starts at the source")
    }

    func testHealingTakesTheTargetsBrightness() throws {
        let s = studio()
        let dark = CodableColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1), light = CodableColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        fill(s, CGRect(x: 0, y: 0, width: 20, height: 20), dark); fill(s, CGRect(x: 20, y: 0, width: 20, height: 20), light)
        s.setCloneSource(CGPoint(x: 10, y: 10))
        let stroke = dab("heal", at: CGPoint(x: 30, y: 10), width: 6)
        XCTAssertTrue(s.beginClone(id: stroke.id, at: CGPoint(x: 30, y: 10)))
        s.add(stroke)
        XCTAssertGreaterThan(try pixel(s, CGPoint(x: 30, y: 10)).red, 0.55, "Healed pixels follow the light target, a clone would be 0.2")
    }

    func testSmudgeDragsColourAlong() throws {
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 20, height: 20), red)
        s.brushSize = 8; s.toolStrength = 0.9
        var stroke = dab("smudge", at: CGPoint(x: 15, y: 10)); stroke.points = [InkPoint(x: 15, y: 10, pressure: 1)]
        s.beginSmudge(id: stroke.id, at: CGPoint(x: 15, y: 10))
        for x in stride(from: 16.0, through: 30, by: 1) { s.smudge(id: stroke.id, to: CGPoint(x: x, y: 10)); stroke.points.append(InkPoint(x: x, y: 10, pressure: 1)) }
        s.add(stroke)
        XCTAssertNil(s.smudgeState)
        let pushed = try pixel(s, CGPoint(x: 24, y: 10))
        XCTAssertGreaterThan(pushed.alpha, 0.3, "Red was pushed into the empty right half")
        XCTAssertEqual(try pixel(s, CGPoint(x: 35, y: 2)).alpha, 0, "Untouched pixels stay empty")
    }

    func testDodgeLightensBurnDarkensAndTransparencyStays() throws {
        let grey = CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        for (kind, lighter) in [("dodge", true), ("burn", false)] {
            let s = studio()
            fill(s, CGRect(x: 0, y: 0, width: 20, height: 20), grey)
            s.add(dab(kind, at: CGPoint(x: 10, y: 10), width: 12, strength: 1))
            s.add(dab(kind, at: CGPoint(x: 30, y: 10), width: 12, strength: 1))
            let v = try pixel(s, CGPoint(x: 10, y: 10)).red
            XCTAssertTrue(lighter ? v > 0.6 : v < 0.4, "\(kind): \(v)")
            XCTAssertEqual(try pixel(s, CGPoint(x: 30, y: 10)).alpha, 0, "\(kind) adds nothing on empty pixels")
        }
    }

    func testBlurBrushSoftensAnEdgeOnlyUnderTheBrush() throws {
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 20, height: 20), red); fill(s, CGRect(x: 20, y: 0, width: 20, height: 20), blue)
        s.add(dab("blurBrush", at: CGPoint(x: 20, y: 10), width: 10, strength: 1))
        let edge = try pixel(s, CGPoint(x: 20, y: 10))
        XCTAssertTrue(edge.red > 0.15 && edge.blue > 0.15, "Mixed at the edge")
        XCTAssertGreaterThan(try pixel(s, CGPoint(x: 20, y: 1)).blue, 0.95, "Sharp outside the brush")
    }
}
