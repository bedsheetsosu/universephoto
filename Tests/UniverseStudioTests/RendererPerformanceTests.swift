import XCTest
import Foundation
@testable import UniverseStudio

/// Fixed synthetic workload; output reports wall-clock render cost, not display FPS or input latency.
final class RendererPerformanceTests: XCTestCase {
    private func fixture() -> [ArtLayer] {
        var layers: [ArtLayer] = []
        for layerIndex in 0..<4 {
            var layer = ArtLayer(name: "Benchmark \(layerIndex)")
            for strokeIndex in 0..<20 {
                var points: [InkPoint] = []
                for i in 0..<64 {
                    let x = Double(i) * 16 + 60
                    let wave = sin(Double(i) * 0.2 + Double(layerIndex)) * 15
                    let y = 70 + Double(strokeIndex) * 30 + wave
                    points.append(InkPoint(x:x,y:y,pressure:0.3 + Double(i % 8) / 12))
                }
                let c = CodableColor(red:Double(layerIndex)/4,green:0.4,blue:0.8,alpha:0.75)
                layer.strokes.append(InkStroke(points:points,color:c,width:12))
            }
            layers.append(layer)
        }
        return layers
    }
    func testFixed1200x800PreviewBenchmark() throws {
        let layers = fixture()
        var preview = InkStroke(points:(0..<100).map { InkPoint(x:Double($0)*10,y:400+sin(Double($0)*0.1)*40,pressure:0.8) },color:.black,width:14)
        let cache = LayerImageCache()
        _ = Renderer.render(layers:layers,width:1200,height:800,cache:cache) // warm the same path used by canvas
        var elapsed: [Double] = []
        for i in 0..<10 {
            preview.points[99].y = 400 + Double(i)
            let start = ContinuousClock.now
            let result = try XCTUnwrap(Renderer.render(layers:layers,width:1200,height:800,preview:preview,previewLayer:3,cache:cache))
            let duration = start.duration(to:.now).components
            elapsed.append(Double(duration.seconds)*1000 + Double(duration.attoseconds)/1e15)
            XCTAssertEqual(result.width,1200); XCTAssertEqual(result.height,800)
        }
        let uncached = try XCTUnwrap(Renderer.render(layers:layers,width:1200,height:800,preview:preview,previewLayer:3))
        let cached = try XCTUnwrap(Renderer.render(layers:layers,width:1200,height:800,preview:preview,previewLayer:3,cache:cache))
        XCTAssertEqual(try Renderer.png(uncached),try Renderer.png(cached),"Layer caching must preserve exact pixels")
        let sorted = elapsed.sorted()
        print(String(format:"RENDER_BENCHMARK 1200x800; 4 layers; 80 strokes x64 points; 100-point preview; 10 warm samples; median=%.3fms; p90=%.3fms; max=%.3fms",(sorted[4]+sorted[5])/2,sorted[8],sorted[9]))
    }
    func testCachedLayerStillCompositesChangedTransformAndOpacity() throws {
        var layer = ArtLayer(name:"Cache")
        layer.strokes = [InkStroke(points:[InkPoint(x:4,y:4,pressure:1)],color:.white,width:4)]
        let cache = LayerImageCache()
        _ = Renderer.render(layers:[layer],width:20,height:20,cache:cache)
        layer.transform.x = 8; layer.opacity = 0.4
        let result = try XCTUnwrap(Renderer.render(layers:[layer],width:20,height:20,cache:cache))
        XCTAssertLessThan(Renderer.sample(result,at:CGPoint(x:4,y:4)).alpha,0.01)
        XCTAssertEqual(Renderer.sample(result,at:CGPoint(x:12,y:4)).alpha,0.4,accuracy:0.02)
    }
}
