import XCTest
import CoreGraphics
@testable import UniversePhoto

final class CanvasGeometryTests: XCTestCase {
    func testCenterAndFitLeaveDocumentMargins() {
        let g = CanvasGeometry(size:CGSize(width:1000,height:700), document:CGSize(width:1200,height:800), zoom:1,pan:.zero,rotation:0,mirrored:false)
        let center = CGPoint(x:600,y:400).applying(g.transform)
        XCTAssertEqual(center.x,500,accuracy:0.0001); XCTAssertEqual(center.y,350,accuracy:0.0001)
        XCTAssertGreaterThanOrEqual(CGPoint.zero.applying(g.transform).x,36)
        XCTAssertGreaterThanOrEqual(CGPoint.zero.applying(g.transform).y,36)
    }
    func testInverseSurvivesZoomPanRotationAndMirror() {
        for mirrored in [false,true] {
            let g = CanvasGeometry(size:CGSize(width:927,height:641),document:CGSize(width:1200,height:800),zoom:2.4,pan:CGSize(width:-51,height:38),rotation:37,mirrored:mirrored)
            for p in [CGPoint.zero,CGPoint(x:600,y:400),CGPoint(x:1199,y:799)] {
                let result = g.toDocument(p.applying(g.transform))
                XCTAssertEqual(result.x,p.x,accuracy:0.0001); XCTAssertEqual(result.y,p.y,accuracy:0.0001)
            }
        }
    }
    func testMirrorKeepsCenterAndReversesHorizontalDirection() {
        let g = CanvasGeometry(size:CGSize(width:1000,height:700),document:CGSize(width:1000,height:600),zoom:1,pan:.zero,rotation:0,mirrored:true)
        let left = CGPoint(x:100,y:300).applying(g.transform), right = CGPoint(x:900,y:300).applying(g.transform)
        XCTAssertGreaterThan(left.x,right.x); XCTAssertEqual((left.x+right.x)/2,500,accuracy:0.0001)
        XCTAssertEqual(left.y,right.y,accuracy:0.0001)
    }
    func testDocumentPointOutsideCanvasIsNotClampedOntoAnEdge() {
        let g = CanvasGeometry(size:CGSize(width:1000,height:700),document:CGSize(width:1200,height:800),zoom:1,pan:.zero,rotation:0,mirrored:false)
        let result = g.toDocument(CGPoint(x:-20,y:-20))
        XCTAssertLessThan(result.x,0); XCTAssertLessThan(result.y,0)
    }
}
