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

    func testSpongeChangesColourOnlyUnderTheBrush() throws {
        let muted = CodableColor(red: 0.7, green: 0.4, blue: 0.4, alpha: 1)
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 40, height: 20), muted)
        s.add(dab("desaturate", at: CGPoint(x: 10, y: 10), width: 12, strength: 1))
        s.add(dab("saturate", at: CGPoint(x: 30, y: 10), width: 12, strength: 1))
        let grey = try pixel(s, CGPoint(x: 10, y: 10)), vivid = try pixel(s, CGPoint(x: 30, y: 10))
        XCTAssertLessThan(abs(grey.red - grey.blue), 0.05, "fully desaturated is grey")
        XCTAssertGreaterThan(vivid.red - vivid.blue, 0.35, "more colour than the 0.3 it had")
        XCTAssertEqual(try pixel(s, CGPoint(x: 20, y: 1)).red, 0.7, accuracy: 0.02, "between the dabs nothing changes")
        XCTAssertEqual(try pixel(s, CGPoint(x: 10, y: 10)).alpha, 1, accuracy: 0.01)
    }

    func testAutoContrastStretchesToBlackAndWhite() throws {
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 20, height: 20), CodableColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1))
        fill(s, CGRect(x: 20, y: 0, width: 20, height: 20), CodableColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1))
        XCTAssertTrue(s.autoContrast())
        XCTAssertLessThan(try pixel(s, CGPoint(x: 10, y: 10)).red, 0.03)
        XCTAssertGreaterThan(try pixel(s, CGPoint(x: 30, y: 10)).red, 0.97)
        let first = s.activeLayer!.adjustment
        XCTAssertTrue(s.autoContrast())
        XCTAssertEqual(s.activeLayer!.adjustment.levelsBlack, first.levelsBlack, accuracy: 0.001, "measures without its own levels: stable")
    }

    func testAutoToneRemovesAColourCast() throws {
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 20, height: 20), CodableColor(red: 0.4, green: 0.2, blue: 0.2, alpha: 1))
        fill(s, CGRect(x: 20, y: 0, width: 20, height: 20), CodableColor(red: 0.9, green: 0.7, blue: 0.7, alpha: 1))
        XCTAssertTrue(s.autoTone())
        let dark = try pixel(s, CGPoint(x: 10, y: 10)), light = try pixel(s, CGPoint(x: 30, y: 10))
        XCTAssertLessThan(abs(dark.red - dark.green), 0.04, "cast gone in the shadows")
        XCTAssertLessThan(abs(light.red - light.green), 0.04, "and in the lights")
        XCTAssertNotNil(s.activeLayer!.adjustment.curves?["red"])
    }

    func testAutoOnAnEmptyLayerDoesNothing() {
        let s = studio()
        XCTAssertFalse(s.autoContrast())
        XCTAssertFalse(s.autoTone())
    }

    func testDefineAndFillWithPattern() throws {
        let s = studio(); s.patternStore = nil; s.patterns = []
        fill(s, CGRect(x: 0, y: 0, width: 2, height: 4), red); fill(s, CGRect(x: 2, y: 0, width: 2, height: 4), blue)
        XCTAssertFalse(s.definePattern(), "needs a selection")
        s.selection = CanvasSelection(points: [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 4)])
        XCTAssertTrue(s.definePattern())
        XCTAssertEqual(s.patterns.count, 1)
        // Fill a fresh layer, only inside x 20…40.
        s.newLayer()
        s.selection = CanvasSelection(points: [CGPoint(x: 20, y: 0), CGPoint(x: 40, y: 20)])
        XCTAssertTrue(s.fillWithPattern(0))
        let a = try pixel(s, CGPoint(x: 20.5, y: 10.5)), b = try pixel(s, CGPoint(x: 22.5, y: 10.5))
        XCTAssertGreaterThan(a.red, 0.9); XCTAssertGreaterThan(b.blue, 0.9)   // tiles line up with the document grid
        XCTAssertGreaterThan(try pixel(s, CGPoint(x: 24.5, y: 2.5)).red, 0.9, "repeats every 4 px")
        s.layers[0].visible = false
        XCTAssertEqual(try pixel(s, CGPoint(x: 10.5, y: 10.5)).alpha, 0, "nothing outside the selection")
    }

    func testPatternsStayAtTwelve() {
        let s = studio(); s.patternStore = nil
        s.patterns = Array(repeating: Data([1]), count: 12)
        fill(s, CGRect(x: 0, y: 0, width: 4, height: 4), red)
        s.selection = CanvasSelection(points: [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 4)])
        XCTAssertTrue(s.definePattern())
        XCTAssertEqual(s.patterns.count, 12)
        XCTAssertNotEqual(s.patterns[0], Data([1]), "newest first")
    }

    func testEyedropperAveragesAndCanIgnoreOtherLayers() throws {
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 20, height: 20), red); fill(s, CGRect(x: 20, y: 0, width: 20, height: 20), blue)
        s.eyedropperAllLayers = true
        s.eyedropperSize = 1
        XCTAssertEqual(try XCTUnwrap(s.pickColor(at: CGPoint(x: 19.5, y: 10))).red, 1, accuracy: 0.01)
        s.eyedropperSize = 3       // 3×3 across the edge: 2 columns red, 1 blue... centred on x 20 → 1 red, 2 blue
        let mixed = try XCTUnwrap(s.pickColor(at: CGPoint(x: 20.5, y: 10)))
        XCTAssertEqual(mixed.red, 1.0 / 3, accuracy: 0.02); XCTAssertEqual(mixed.blue, 2.0 / 3, accuracy: 0.02)
        // A new empty layer on top: "all layers" still sees red, the layer alone sees nothing.
        s.newLayer()
        s.eyedropperSize = 1
        XCTAssertNotNil(s.pickColor(at: CGPoint(x: 5, y: 5)))
        s.eyedropperAllLayers = false
        XCTAssertNil(s.pickColor(at: CGPoint(x: 5, y: 5)))
        s.eyedropperAllLayers = true
    }

    func testReplaceColorShiftsOnlyTheMatchingColour() throws {
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 20, height: 20), red); fill(s, CGRect(x: 20, y: 0, width: 20, height: 20), blue)
        var rep = ColorReplacement(source: red); rep.hue = 120; rep.fuzziness = 30
        XCTAssertEqual(s.replaceColor(rep), 400)
        let a = try pixel(s, CGPoint(x: 10, y: 10)), b = try pixel(s, CGPoint(x: 30, y: 10))
        XCTAssertGreaterThan(a.green, 0.95); XCTAssertLessThan(a.red, 0.05)   // red turned green
        XCTAssertGreaterThan(b.blue, 0.95); XCTAssertLessThan(b.green, 0.05)  // blue untouched
        XCTAssertEqual(try pixel(s, CGPoint(x: 10, y: 10)).alpha, 1, accuracy: 0.01)
        s.undo()
        XCTAssertGreaterThan(try pixel(s, CGPoint(x: 10, y: 10)).red, 0.95)
    }

    func testReplaceColorRespectsTheSelectionAndLightness() throws {
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 40, height: 20), red)
        s.selection = CanvasSelection(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 20)])
        var rep = ColorReplacement(source: red); rep.lightness = -100
        XCTAssertEqual(s.replaceColor(rep), 200)
        XCTAssertLessThan(try pixel(s, CGPoint(x: 5, y: 10)).red, 0.05, "black inside")
        XCTAssertGreaterThan(try pixel(s, CGPoint(x: 30, y: 10)).red, 0.95, "outside stays")
        XCTAssertEqual(s.replaceColor(ColorReplacement(source: CodableColor(red: 0, green: 1, blue: 0, alpha: 1), fuzziness: 10)), 0, "nothing green")
    }

    func testHSLRoundTrip() {
        for (r, g, b) in [(0.2, 0.5, 0.9), (1.0, 1.0, 1.0), (0.3, 0.3, 0.3), (0.9, 0.1, 0.4)] {
            let (h, sat, l) = ColorReplacement.hsl(r, g, b), (r2, g2, b2) = ColorReplacement.rgb(h, sat, l)
            XCTAssertEqual(r, r2, accuracy: 0.0001); XCTAssertEqual(g, g2, accuracy: 0.0001); XCTAssertEqual(b, b2, accuracy: 0.0001)
        }
    }

    func testLoadLayerTransparencyFollowsTheLayerAndCombines() throws {
        let s = studio()
        fill(s, CGRect(x: 0, y: 0, width: 10, height: 10), red)
        s.layers[s.selectedLayer].transform.x = 5            // moved 5 px right on the canvas
        s.loadLayerTransparency()
        var m = try XCTUnwrap(s.selectionMask())
        XCTAssertEqual(m[5 * 40 + 6], 255); XCTAssertEqual(m[5 * 40 + 2], 0)
        // ⌥: subtract a rectangle-shaped layer's pixels.
        s.newLayer(); fill(s, CGRect(x: 10, y: 0, width: 10, height: 10), blue)
        s.loadLayerTransparency(s.selectedLayer, .subtract)
        m = try XCTUnwrap(s.selectionMask())
        XCTAssertEqual(m[5 * 40 + 6], 255); XCTAssertEqual(m[5 * 40 + 12], 0)
        // Intersect with nothing selected gives nothing.
        s.selection = nil
        s.loadLayerTransparency(s.selectedLayer, .intersect)
        XCTAssertNil(s.selection)
    }

    func testSaveAndLoadSelection() throws {
        let s = studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        s.saveSelection(); s.selection = nil
        XCTAssertTrue(s.hasSavedSelection)
        s.loadSavedSelection()
        XCTAssertEqual(try XCTUnwrap(s.selectionMask())[5 * 40 + 5], 255)
        XCTAssertEqual(Studio.maskCombine([.shift, .option]), .intersect)
    }

    func testBrushBlendModesMixWithTheLayer() throws {
        for (mode, expect) in [(LayerBlend.normal, (0.0, 0.0, 1.0)), (.multiply, (0.0, 0.0, 0.0)), (.screen, (1.0, 0.0, 1.0))] {
            let s = studio()
            fill(s, CGRect(x: 0, y: 0, width: 40, height: 20), red)
            var b = InkStroke(points: [InkPoint(x: 5, y: 10, pressure: 1), InkPoint(x: 35, y: 10, pressure: 1)], color: blue, width: 8)
            b.blend = mode == .normal ? nil : mode
            s.add(b)
            let p = try pixel(s, CGPoint(x: 20, y: 10))
            XCTAssertEqual(p.red, expect.0, accuracy: 0.03, "\(mode)"); XCTAssertEqual(p.green, expect.1, accuracy: 0.03, "\(mode)"); XCTAssertEqual(p.blue, expect.2, accuracy: 0.03, "\(mode)")
            XCTAssertGreaterThan(try pixel(s, CGPoint(x: 20, y: 2)).red, 0.95, "outside the stroke the layer stays")
        }
    }
}
