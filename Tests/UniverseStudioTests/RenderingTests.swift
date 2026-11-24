import XCTest
import ImageIO
@testable import UniverseStudio

final class RenderingTests: XCTestCase {
    private let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
    private func dot(_ x: Double, _ y: Double, color: CodableColor, width: Double = 10, erase: Bool = false, pressure: Double = 1) -> InkStroke {
        InkStroke(points: [InkPoint(x: x, y: y, pressure: pressure)], color: color, width: width, isEraser: erase)
    }
    func testEraserClearsOnlyItsOwnLayerAndPreservesAlpha() throws {
        var bottom = ArtLayer(name: "Bottom"); bottom.strokes = [dot(16,16,color:blue)]
        var top = ArtLayer(name: "Top"); top.strokes = [dot(16,16,color:red), dot(16,16,color:red,width:5,erase:true)]
        let topImage = try XCTUnwrap(Renderer.render(layers: [top], width: 32, height: 32))
        XCTAssertLessThan(Renderer.sample(topImage,at:CGPoint(x:16,y:16)).alpha, 0.01)
        let combined = try XCTUnwrap(Renderer.render(layers:[bottom,top],width:32,height:32))
        XCTAssertGreaterThan(Renderer.sample(combined,at:CGPoint(x:16,y:16)).blue, 0.99)
        XCTAssertGreaterThan(Renderer.sample(combined,at:CGPoint(x:19,y:16)).red, 0.8)
    }
    func testOpacityBlendAndTranslation() throws {
        var bottom = ArtLayer(name: "White"); bottom.strokes = [InkStroke(points:[InkPoint(x:0,y:0,pressure:1)],color:.white,width:1,kind:"fill")]
        var top = ArtLayer(name: "Red"); top.strokes = [dot(8,8,color:red,width:6)]; top.opacity = 0.5; top.transform.x = 8; top.blend = .multiply
        let image = try XCTUnwrap(Renderer.render(layers:[bottom,top],width:32,height:32))
        let source = Renderer.sample(image,at:CGPoint(x:8,y:8)), moved = Renderer.sample(image,at:CGPoint(x:16,y:8))
        XCTAssertGreaterThan(source.green, 0.99)
        XCTAssertEqual(moved.red,1,accuracy:0.02); XCTAssertEqual(moved.green,0.5,accuracy:0.03)
    }
    func testPNGKeepsDocumentCoordinateOrientation() throws {
        var layer = ArtLayer(name: "Asymmetric"); layer.strokes = [dot(5,4,color:red,width:4),dot(5,25,color:blue,width:4)]
        let image = try XCTUnwrap(Renderer.render(layers:[layer],width:32,height:32))
        let data = try Renderer.png(image)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
        let loaded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertGreaterThan(Renderer.sample(loaded,at:CGPoint(x:5,y:4)).red,0.99)
        XCTAssertGreaterThan(Renderer.sample(loaded,at:CGPoint(x:5,y:25)).blue,0.99)
    }
    func testPressureChangesStrokeWidthAndSingleClickDraws() throws {
        var layer = ArtLayer(name: "Pressure"); layer.strokes = [dot(8,8,color:red,width:12,pressure:0.2),dot(24,8,color:red,width:12)]
        let image = try XCTUnwrap(Renderer.render(layers:[layer],width:40,height:20))
        XCTAssertGreaterThan(Renderer.sample(image,at:CGPoint(x:8,y:8)).alpha,0.8)
        XCTAssertLessThan(Renderer.sample(image,at:CGPoint(x:8,y:12)).alpha,0.01)
        XCTAssertGreaterThan(Renderer.sample(image,at:CGPoint(x:24,y:12)).alpha,0.8)
    }
    func testBlackMaskHidesAndWhiteReveals() throws {
        var layer = ArtLayer(name: "Mask"); layer.strokes = [InkStroke(points:[InkPoint(x:0,y:0,pressure:1)],color:red,width:1,kind:"fill")]
        layer.mask = [dot(8,8,color:.black,width:8),dot(8,8,color:.white,width:2)]
        let image = try XCTUnwrap(Renderer.render(layers:[layer],width:20,height:20))
        XCTAssertGreaterThan(Renderer.sample(image,at:CGPoint(x:8,y:8)).alpha,0.7)
        XCTAssertLessThan(Renderer.sample(image,at:CGPoint(x:10,y:8)).alpha,0.2)
        XCTAssertGreaterThan(Renderer.sample(image,at:CGPoint(x:16,y:16)).alpha,0.99)
    }
    func testSelectionPersistsAndClipsFill() throws {
        var layer = ArtLayer(name: "Selection")
        var stroke = InkStroke(points: [InkPoint(x:0,y:0,pressure:1)], color:red, width:1, kind:"fill")
        stroke.selectionPoints = [InkPoint(x:5,y:5,pressure:1),InkPoint(x:15,y:15,pressure:1)]
        layer.strokes = [stroke]
        let image = try XCTUnwrap(Renderer.render(layers:[layer],width:20,height:20))
        XCTAssertGreaterThan(Renderer.sample(image,at:CGPoint(x:10,y:10)).alpha,0.99)
        XCTAssertLessThan(Renderer.sample(image,at:CGPoint(x:3,y:3)).alpha,0.01)
    }

    func testPressureSegmentContinuityAndConstantOpacityAtJoins() throws {
        var layer = ArtLayer(name: "Continuous")
        let color = CodableColor(red:1,green:0,blue:0,alpha:0.5)
        layer.strokes = [InkStroke(points:[InkPoint(x:5,y:10,pressure:0.5),InkPoint(x:15,y:10,pressure:1),InkPoint(x:25,y:10,pressure:0.5)],color:color,width:8)]
        let image = try XCTUnwrap(Renderer.render(layers:[layer],width:32,height:24))
        for x in 5...25 {
            XCTAssertEqual(Renderer.sample(image,at:CGPoint(x:x,y:10)).alpha,0.5,accuracy:0.02)
        }
    }

}
