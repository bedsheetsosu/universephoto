import Foundation

/// Animation → Effects → Lighting → Flash to the beat (0.282): on every beat the picture lights up
/// white and fades out quickly – a club light, a camera flash rhythm. One full-picture layer on top
/// with Screen blending whose opacity follows the beat (real frame times, holds included). Pairs with
/// Pump to the beat. One undo step.
extension Studio {
    static func beatFlash(_ phase: Double, strength: Double) -> Double {
        let p = phase - phase.rounded(.down)
        return strength * pow(max(0, 1 - p / 0.35), 2)
    }

    @discardableResult func addBeatFlash(bpm: Double, strength: Double = 0.5) -> Int {
        guard frames.count >= 2, bpm > 0 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let start = AudioTiming.time(ofFrame: r.lowerBound, fps: fps, hold: hold)
        checkpoint("Flash to the beat")
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 1, blue: 1, alpha: 1), width: 1)
        fill.kind = "fill"
        var layer = ArtLayer(name: L("Flash to the beat")); layer.strokes = [fill]; layer.blend = .screen
        for i in frames.indices {
            var l = layer
            l.opacity = r.contains(i) ? Studio.beatFlash((AudioTiming.time(ofFrame: i, fps: fps, hold: hold) - start) * bpm / 60, strength: strength) : 0
            frames[i].append(l)
        }
        layers = frames[frameIndex]; selectedLayer = layers.count - 1
        changed()
        return r.count
    }
}
