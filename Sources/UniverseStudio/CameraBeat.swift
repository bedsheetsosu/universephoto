import Foundation

/// Animation → Effects → Camera → Pump to the beat (0.281): the music-video punch – on every beat the
/// whole picture zooms in a little and eases back out before the next one. Beats follow the real
/// frame times (holds included) at the chosen tempo, from the start of the play range (or frame 1).
/// Every layer scales around the middle of the canvas, shared backgrounds included. One undo step.
extension Studio {
    /// Extra zoom at `phase` within a beat: full right on the beat, eased out over the beat.
    static func beatZoom(_ phase: Double, amount: Double) -> Double {
        let p = phase - phase.rounded(.down)
        return amount * pow(1 - p, 3)
    }

    @discardableResult func cameraBeat(bpm: Double, amount: Double = 0.05) -> Int {
        guard frames.count >= 2, bpm > 0, amount > 0 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let start = AudioTiming.time(ofFrame: r.lowerBound, fps: fps, hold: hold)
        checkpoint("Pump to the beat")
        frames = Studio.unsharedForCamera(frames)
        for i in r {
            let f = 1 + Studio.beatZoom((AudioTiming.time(ofFrame: i, fps: fps, hold: hold) - start) * bpm / 60, amount: amount)
            guard f > 1 + 1e-9 else { continue }
            for j in frames[i].indices where !frames[i][j].locked {
                frames[i][j].transform.scale *= f
                frames[i][j].transform.x *= f; frames[i][j].transform.y *= f
            }
        }
        layers = frames[frameIndex]; changed()
        return r.count
    }
}
