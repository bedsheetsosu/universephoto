import Foundation
import CoreGraphics

/// Animation → Effects → Countdown (0.215): a big 3 – 2 – 1 (or from 5, or 10) in the middle of the
/// picture, one number per second. Each number pops in a little too large, settles and fades out
/// at the end of its second. The current frame becomes the first one; the rest of the picture stays
/// as it is. On a new layer on top, in the brush colour. One undo step. Returns the frames made.
extension Studio {
    /// Font-size factor and opacity for frame `j` of `per` frames that one number is shown.
    static func countdownLook(frame j: Int, of per: Int) -> (size: Double, alpha: Double) {
        let t = Double(j) / Double(max(1, per))
        let pop = max(0, 1 - t / 0.25)                  // first quarter: shrinks from 1.5× to 1×
        let fade = t > 0.75 ? max(0, 1 - (t - 0.75) / 0.25) : 1
        return (1 + 0.5 * pop * pop, fade)
    }

    @discardableResult func countdown(from start: Int) -> Int {
        guard start >= 1 else { return 0 }
        stopPlayback(); checkpoint("Countdown")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let per = max(2, Int(fps.rounded())), base = Double(min(width, height)) * 0.45
        let source = frames[frameIndex], id = UUID()
        var made: [[ArtLayer]] = []
        for n in stride(from: start, through: 1, by: -1) {
            for j in 0..<per {
                let look = Studio.countdownLook(frame: j, of: per), size = base * look.size
                var c = color; c.alpha *= look.alpha
                var s = InkStroke(points: [InkPoint(x: Double(width) / 2, y: Double(height) / 2 - size * 0.64, pressure: 1)], color: c, width: size)
                s.kind = "text"; s.text = "\(n)"; s.fontName = "Helvetica-Bold"; s.textAlign = "center"
                var layer = ArtLayer(name: L("Countdown")); layer.id = id
                layer.strokes = look.alpha > 0.01 ? [s] : []
                made.append(source + [layer])
            }
        }
        frames[frameIndex] = made[0]
        metaInsert(at: frameIndex + 1, holds: Array(repeating: 1, count: made.count - 1))
        frames.insert(contentsOf: made.dropFirst(), at: frameIndex + 1)
        layers = frames[frameIndex]
        selectedLayer = layers.count - 1
        changed()
        return made.count
    }
}
