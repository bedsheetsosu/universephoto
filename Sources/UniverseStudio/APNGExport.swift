import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Animated PNG (0.84): full 8-bit transparency and colours (GIF has 256 colours and on/off
/// transparency). Each frame is stored once with its hold as its delay.
extension ImageFiles {
    static func exportAPNG(frames: [[ArtLayer]], holds: [Int], width docW: Int, height docH: Int, fps: Double, scale: Double = 1, loopForever: Bool = true, url: URL) throws {
        let (width, height) = outputSize(docW, docH, scale: scale)
        try validateAnimation(frames: frames, width: width, height: height, fps: fps)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, frames.count, nil) else { throw FileError.encoder("APNG") }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: loopForever ? 0 : 1]] as CFDictionary)
        for (i, frame) in frames.enumerated() {
            guard let image = renderFrame(frame, docW, docH, width, height) else { throw FileError.encoder("APNG frame") }
            let delay = Double(holds.indices.contains(i) ? max(1, holds[i]) : 1) / max(1, fps)
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay, kCGImagePropertyAPNGUnclampedDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw FileError.encoder("Could not finish the APNG export") }
        try (data as Data).write(to: url, options: .atomic)
    }
}
