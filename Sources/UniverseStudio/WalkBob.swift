import Foundation
import CoreGraphics

/// Animation → Layer effects → Walk bob (0.214): the active layer bobs up with every step and tips a
/// little from foot to foot – a figure walking or a box waddling, on top of its own motion (pair it
/// with Travel). `steps` steps over the play range (or all frames), a seamless loop. Tips around the
/// bottom of the drawing. One undo step. Returns how many frames changed.
extension Studio {
    /// (lift in px upwards, tilt in degrees) for frame `k` of `n` with `steps` steps.
    static func walkBob(frame k: Int, of n: Int, steps: Int, height: Double, tilt: Double) -> (lift: Double, tilt: Double) {
        guard n > 0, steps > 0 else { return (0, 0) }
        let phase = Double(k) / Double(n) * Double(steps)      // 0 … steps
        return (height * abs(sin(.pi * phase)), tilt * sin(.pi * phase))   // tilt flips with each step
    }

    @discardableResult func walkBob(steps: Int, height: Double, tilt: Double) -> Int {
        guard frames.count >= 2, steps > 0, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, changedFrames = 0
        for (k, i) in r.enumerated() {
            let b = Studio.walkBob(frame: k, of: r.count, steps: steps, height: height, tilt: tilt)
            guard abs(b.lift) > 1e-9 || abs(b.tilt) > 1e-9 else { continue }
            for j in nf[i].indices where nf[i][j].id == id {
                pivotEdit(&nf[i][j], .bottom) { $0.rotation += b.tilt }
                nf[i][j].transform.y -= b.lift
                changedFrames += 1
            }
        }
        guard changedFrames > 0 else { return 0 }
        checkpoint("Walk bob")
        frames = nf; layers = frames[frameIndex]; changed()
        return changedFrames
    }
}
