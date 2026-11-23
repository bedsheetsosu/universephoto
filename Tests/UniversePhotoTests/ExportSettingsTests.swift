import CoreGraphics
import Testing
import UniformTypeIdentifiers
@testable import UniversePhoto

struct ExportSettingsTests {
    func noisy(_ w: Int, _ h: Int) throws -> CGImage {
        let ctx = try #require(Renderer.context(width: w, height: h))
        var seed: UInt64 = 1
        for y in stride(from: 0, to: h, by: 2) { for x in stride(from: 0, to: w, by: 2) {
            seed = seed &* 6364136223846793005 &+ 1
            ctx.setFillColor(CGColor(srgbRed: Double(seed >> 56) / 255, green: Double((seed >> 48) & 255) / 255, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
        } }
        return try #require(ctx.makeImage())
    }

    @Test func scalingChangesPixelSize() throws {
        let image = try noisy(200, 100)
        let half = try #require(ImageFiles.scaled(image, by: 0.5))
        #expect(half.width == 100 && half.height == 50)
        let same = try #require(ImageFiles.scaled(image, by: 1))
        #expect(same.width == 200)
    }

    @Test func lowerQualityGivesSmallerFiles() throws {
        let image = try noisy(256, 256)
        let high = try ImageFiles.encodedData(image: image, type: .jpeg, quality: 0.95).count
        let low = try ImageFiles.encodedData(image: image, type: .jpeg, quality: 0.3).count
        #expect(low < high)
    }
}
