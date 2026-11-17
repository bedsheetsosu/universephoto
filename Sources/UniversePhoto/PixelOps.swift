import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pixel work on document-sized bitmaps: flood fill, magic wand, selection masks.
/// Everything is in document pixels with y = 0 at the top (row 0 of the byte buffers).
enum PixelOps {
    /// RGBA8, premultiplied, row 0 = top.
    struct Bitmap {
        var width: Int; var height: Int; var bytes: [UInt8]
        func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
    }

    static func bitmap(_ image: CGImage) -> Bitmap? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Bitmap(width: w, height: h, bytes: bytes) : nil
    }

    /// Pixels similar to the one at `seed` (max channel difference ≤ `tolerance`, 0…255).
    /// `contiguous`: only the connected region (scanline fill), else every similar pixel.
    /// Returns one byte per pixel: 255 = inside.
    static func similarRegion(in b: Bitmap, seed: (x: Int, y: Int), tolerance: Int, contiguous: Bool) -> [UInt8] {
        let w = b.width, h = b.height
        var mask = [UInt8](repeating: 0, count: w * h)
        guard seed.x >= 0, seed.y >= 0, seed.x < w, seed.y < h else { return mask }
        let s = b.index(seed.x, seed.y)
        let ref = (Int(b.bytes[s]), Int(b.bytes[s + 1]), Int(b.bytes[s + 2]), Int(b.bytes[s + 3]))
        let tol = max(0, min(255, tolerance))
        @inline(__always) func similar(_ i: Int) -> Bool {
            let p = i * 4
            return abs(Int(b.bytes[p]) - ref.0) <= tol && abs(Int(b.bytes[p + 1]) - ref.1) <= tol
                && abs(Int(b.bytes[p + 2]) - ref.2) <= tol && abs(Int(b.bytes[p + 3]) - ref.3) <= tol
        }
        if !contiguous {
            for i in 0..<(w * h) where similar(i) { mask[i] = 255 }
            return mask
        }
        // Scanline flood fill with an explicit stack (no recursion on large areas).
        var stack = [(seed.x, seed.y)]
        while let (x0, y) = stack.popLast() {
            var x = x0
            let row = y * w
            guard mask[row + x] == 0, similar(row + x) else { continue }
            while x > 0, mask[row + x - 1] == 0, similar(row + x - 1) { x -= 1 }
            var above = false, below = false
            while x < w, mask[row + x] == 0, similar(row + x) {
                mask[row + x] = 255
                if y > 0 {
                    let i = row - w + x, inside = mask[i] == 0 && similar(i)
                    if inside && !above { stack.append((x, y - 1)) }
                    above = inside
                }
                if y < h - 1 {
                    let i = row + w + x, inside = mask[i] == 0 && similar(i)
                    if inside && !below { stack.append((x, y + 1)) }
                    below = inside
                }
                x += 1
            }
        }
        return mask
    }

    /// Grows the region by one pixel so anti-aliased edges are covered (like Photoshop's fill).
    static func grow(_ mask: [UInt8], width w: Int, height h: Int) -> [UInt8] {
        var out = mask
        for y in 0..<h {
            for x in 0..<w where mask[y * w + x] == 0 {
                if (x > 0 && mask[y * w + x - 1] != 0) || (x < w - 1 && mask[y * w + x + 1] != 0)
                    || (y > 0 && mask[(y - 1) * w + x] != 0) || (y < h - 1 && mask[(y + 1) * w + x] != 0) { out[y * w + x] = 255 }
            }
        }
        return out
    }

    /// DeviceGray image (white = selected), usable with `CGContext.clip(to:mask:)`.
    static func grayImage(_ mask: [UInt8], width w: Int, height h: Int) -> CGImage? {
        guard mask.count == w * h, let provider = CGDataProvider(data: Data(mask) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func grayBytes(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? bytes : nil
    }

    /// A colour where the mask is set, transparent elsewhere (RGBA image, document size).
    static func fillImage(_ mask: [UInt8], width w: Int, height h: Int, color: CodableColor) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let a = max(0, min(1, color.alpha))
        let r = UInt8(max(0, min(255, color.red * a * 255))), g = UInt8(max(0, min(255, color.green * a * 255)))
        let bl = UInt8(max(0, min(255, color.blue * a * 255))), al = UInt8(a * 255)
        for i in 0..<(w * h) where mask[i] != 0 {
            let p = i * 4
            bytes[p] = r; bytes[p + 1] = g; bytes[p + 2] = bl; bytes[p + 3] = al
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Selection shape (rectangle, ellipse, lasso) as a mask, so it can be inverted or combined.
    static func mask(for path: CGPath, width w: Int, height h: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: w * h)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)   // path is y-down
            ctx.setFillColor(gray: 1, alpha: 1); ctx.addPath(path); ctx.fillPath()
        }
        return bytes
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(d, image, nil)
        return CGImageDestinationFinalize(d) ? data as Data : nil
    }

    nonisolated(unsafe) private static let grayCache = NSCache<NSData, CGImage>()   // NSCache is thread-safe
    /// Decodes a stored selection mask to DeviceGray (cached: strokes are redrawn often).
    static func decodeGray(_ data: Data) -> CGImage? {
        if let hit = grayCache.object(forKey: data as NSData) { return hit }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let bytes = grayBytes(image), let gray = grayImage(bytes, width: image.width, height: image.height) else { return nil }
        grayCache.setObject(gray, forKey: data as NSData)
        return gray
    }

    /// Bounding box of the set pixels (for the marching outline), nil if empty.
    static func bounds(_ mask: [UInt8], width w: Int, height h: Int) -> CGRect? {
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where mask[y * w + x] != 0 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
