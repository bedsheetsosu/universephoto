import Foundation
import CoreGraphics

/// Animation → Effects → Camera → Follow the active layer (0.244): the camera pans along with the
/// active layer so it stays in view – the whole picture moves the other way. `tight` keeps it
/// almost exactly where it was in the first frame; loose lets it drift a little before the camera
/// catches up. Smoothed, so the pan never jerks. Locked layers stay put; layers that were the same in
/// all frames get a copy per frame (0.246). Works on the play range if set. One undo step.
extension Studio {
    /// Camera offsets per frame to keep `centres` near the first one: a smoothed, scaled pull back.
    static func followOffsets(_ centres: [CGPoint], strength: Double, smooth: Int) -> [CGPoint] {
        guard let first = centres.first else { return [] }
        let raw = centres.map { CGPoint(x: (first.x - $0.x) * strength, y: (first.y - $0.y) * strength) }
        guard smooth > 0 else { return raw }
        return raw.indices.map { i in
            let lo = max(0, i - smooth), hi = min(raw.count - 1, i + smooth), n = Double(hi - lo + 1)
            let sx = raw[lo...hi].reduce(0) { $0 + $1.x }, sy = raw[lo...hi].reduce(0) { $0 + $1.y }
            return i == 0 ? .zero : CGPoint(x: sx / n, y: sy / n)
        }
    }

    @discardableResult func cameraFollow(tight: Bool) -> Int {
        guard frames.count >= 2, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let centre = CGPoint(x: local.midX, y: local.midY)
        let pts: [CGPoint?] = r.map { i in frames[i].first { $0.id == src.id }.map { centre.applying(matrix($0.transform)) } }
        guard pts.allSatisfy({ $0 != nil }) else { return 0 }
        let offs = Studio.followOffsets(pts.map { $0! }, strength: tight ? 1 : 0.75, smooth: tight ? 1 : 3)
        guard offs.contains(where: { abs($0.x) > 0.5 || abs($0.y) > 0.5 }) else { return 0 }
        checkpoint("Camera follow")
        frames = Studio.unsharedForCamera(frames)
        for (k, i) in r.enumerated() {
            for j in frames[i].indices where !frames[i][j].locked {
                frames[i][j].transform.x += offs[k].x; frames[i][j].transform.y += offs[k].y
            }
        }
        layers = frames[frameIndex]; changed()
        return r.count
    }
}
