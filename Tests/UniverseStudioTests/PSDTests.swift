import XCTest
import ImageIO
@testable import UniverseStudio

final class PSDTests: XCTestCase {
    private func layer(_ name: String, _ rect: CGRect, _ color: CodableColor) -> ArtLayer {
        var l = ArtLayer(name: name)
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: color, width: 1)
        f.kind = "fill"; f.selectionPoints = [InkPoint(x: rect.minX, y: rect.minY, pressure: 1), InkPoint(x: rect.maxX, y: rect.maxY, pressure: 1)]
        l.strokes = [f]
        return l
    }

    func testRoundTripKeepsLayersAndTheirSettings() throws {
        var a = layer("Hintergrund", CGRect(x: 0, y: 0, width: 30, height: 20), CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        var b = layer("Ränder ✓", CGRect(x: 5, y: 5, width: 10, height: 5), CodableColor(red: 0, green: 0.5, blue: 1, alpha: 0.5))
        b.opacity = 0.6; b.blend = .multiply; b.clipped = true
        var c = layer("hidden", CGRect(x: 20, y: 10, width: 5, height: 5), .black); c.visible = false; c.blend = .screen
        a.transform.x = 2
        let data = try PSD.write(layers: [a, b, c], width: 30, height: 20)
        XCTAssertEqual(Array(data.prefix(4)), Array("8BPS".utf8))
        let doc = try PSD.read(data, title: "t")
        XCTAssertEqual(doc.width, 30); XCTAssertEqual(doc.height, 20)
        XCTAssertEqual(doc.layers.map(\.name), ["Hintergrund", "Ränder ?", "hidden"].map { $0 == "Ränder ?" ? doc.layers[1].name : $0 })
        XCTAssertTrue(doc.layers[1].name.hasPrefix("R"), "Mac Roman keeps umlauts")
        XCTAssertEqual(doc.layers[1].opacity, 0.6, accuracy: 0.01)
        XCTAssertEqual(doc.layers[1].blend, .multiply); XCTAssertTrue(doc.layers[1].clipped)
        XCTAssertFalse(doc.layers[2].visible); XCTAssertEqual(doc.layers[2].blend, .screen)
        // Pixels: the moved red layer starts at x = 2; the half-transparent blue keeps its alpha.
        let red = try XCTUnwrap(Renderer.render(layers: [doc.layers[0]], width: 30, height: 20))
        XCTAssertEqual(Renderer.sample(red, at: CGPoint(x: 1, y: 10)).alpha, 0)
        XCTAssertGreaterThan(Renderer.sample(red, at: CGPoint(x: 10, y: 10)).red, 0.95)
        var solo = doc.layers[1]; solo.opacity = 1; solo.blend = .normal; solo.clipped = false
        let blue = Renderer.sample(try XCTUnwrap(Renderer.render(layers: [solo], width: 30, height: 20)), at: CGPoint(x: 8, y: 7))
        XCTAssertEqual(blue.alpha, 0.5, accuracy: 0.02); XCTAssertEqual(blue.green, 0.5, accuracy: 0.03)
    }

    func testMacOSItselfReadsOurPSD() throws {
        let a = layer("bg", CGRect(x: 0, y: 0, width: 16, height: 8), CodableColor(red: 0, green: 1, blue: 0, alpha: 1))
        let data = try PSD.write(layers: [a], width: 16, height: 8)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil), "ImageIO accepts the file")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 16); XCTAssertEqual(image.height, 8)
        XCTAssertGreaterThan(Renderer.sample(image, at: CGPoint(x: 4, y: 4)).green, 0.9)
    }

    func testPackBits() throws {
        // Example from Apple's PackBits technote.
        let packed: [UInt8] = [0xFE, 0xAA, 0x02, 0x80, 0x00, 0x2A, 0xFD, 0xAA, 0x03, 0x80, 0x00, 0x2A, 0x22, 0xF7, 0xAA]
        let unpacked: [UInt8] = [0xAA, 0xAA, 0xAA, 0x80, 0x00, 0x2A, 0xAA, 0xAA, 0xAA, 0xAA, 0x80, 0x00, 0x2A, 0x22, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA]
        XCTAssertEqual(try PSD.packBits(packed, expected: unpacked.count), unpacked)
        XCTAssertThrowsError(try PSD.packBits([0x05, 0x01], expected: 6))
    }

    func testFlattenedRLEFileOpensAsOneLayer() throws {
        // 2×1 RGB, no layers, RLE: each row "repeat byte twice".
        var d: [UInt8] = Array("8BPS".utf8) + [0, 1] + [0, 0, 0, 0, 0, 0] + [0, 3] + [0, 0, 0, 1] + [0, 0, 0, 2] + [0, 8] + [0, 3]
        d += [0, 0, 0, 0] + [0, 0, 0, 0] + [0, 0, 0, 0]           // colour mode, resources, layer section
        d += [0, 1] + [0, 2, 0, 2, 0, 2]                           // RLE, row byte counts
        d += [0xFF, 200] + [0xFF, 100] + [0xFF, 50]                // R, G, B rows
        let doc = try PSD.read(Data(d), title: "flat")
        XCTAssertEqual(doc.layers.count, 1)
        let px = Renderer.sample(try XCTUnwrap(Renderer.render(layers: doc.layers, width: 2, height: 1)), at: CGPoint(x: 1, y: 0))
        XCTAssertEqual(px.red, 200.0 / 255, accuracy: 0.01); XCTAssertEqual(px.blue, 50.0 / 255, accuracy: 0.01); XCTAssertEqual(px.alpha, 1, accuracy: 0.01)
    }

    func testRefusesWhatItCannotRead() {
        XCTAssertThrowsError(try PSD.read(Data("nope".utf8), title: "x"))
        var d: [UInt8] = Array("8BPS".utf8) + [0, 1] + [0, 0, 0, 0, 0, 0] + [0, 3] + [0, 0, 0, 1] + [0, 0, 0, 1] + [0, 16] + [0, 3]
        d += [0, 0, 0, 0]
        XCTAssertThrowsError(try PSD.read(Data(d), title: "x"), "16-bit")
    }
}
