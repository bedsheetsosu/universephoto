import CoreGraphics
import CoreVideo
import Testing
@testable import UniversePhoto

struct SubjectMaskTests {
    @Test func floatBufferBecomesMaskBytes() throws {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 4, 2, kCVPixelFormatType_OneComponent32Float, nil, &pb)
        let buffer = try #require(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)), row = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<2 { let line = base.advanced(by: y * row).assumingMemoryBound(to: Float32.self); for x in 0..<4 { line[x] = x >= 2 ? 1 : 0 } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        // Scaled up 2× it keeps left = background, right = subject, row 0 = top.
        let m = try #require(SubjectMask.bytes(buffer, width: 8, height: 4))
        #expect(m[0] == 0 && m[3] == 0 && m[4] == 255 && m[7] == 255 && m[31] == 255)
    }

    @Test func emptyPictureHasNoSubject() throws {
        let ctx = try #require(Renderer.context(width: 64, height: 64))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try #require(ctx.makeImage())
        // A blank white picture: either no mask or one with (almost) nothing selected.
        let m = try SubjectMask.mask(for: image)
        #expect(m == nil || m!.filter { $0 > 128 }.count < 64 * 64 / 10)
    }
}
