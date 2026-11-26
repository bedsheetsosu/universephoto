import Foundation

/// Animation → Effects → Handheld camera (0.243): the whole picture sways gently as if filmed from
/// the hand – a soft, random, seamless drift with a hint of turn, over the existing frames (or the
/// play range). Every layer moves by the same amount around the middle of the canvas; layers that
/// are the same in all frames and locked layers stay put. One undo step.
extension Studio {
    @discardableResult func handheldCamera(amount: Double, seed: UInt64 = 0xCA3) -> Int {
        guard frames.count >= 2, amount > 0 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let (dx, dy) = Studio.wanderOffset(k, of: r.count, radius: amount, seed: seed)
            let turn = Studio.wanderOffset(k, of: r.count, radius: amount * 0.04, seed: seed &+ 1).0   // degrees
            guard abs(dx) > 1e-9 || abs(dy) > 1e-9 || abs(turn) > 1e-9 else { continue }
            let a = turn * .pi / 180, c = cos(a), s = sin(a)
            for j in nf[i].indices where !nf[i][j].locked && nf[i][j].allFrames != true {
                // Turn around the canvas middle: the layer's offset from the middle turns too.
                let x = nf[i][j].transform.x, y = nf[i][j].transform.y
                nf[i][j].transform.x = x * c - y * s + dx
                nf[i][j].transform.y = x * s + y * c + dy
                nf[i][j].transform.rotation += turn
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Handheld camera")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
