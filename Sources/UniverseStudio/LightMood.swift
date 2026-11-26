import Foundation

/// Animation → Effects → Light → Day to night / Night to day / Sunset (0.247): the light of the
/// whole picture changes over the frames – a coloured layer on top (multiply for night, soft light
/// for a warm sunset) fades in or out with a soft ease. Before the play range it is at its start,
/// after it at its end. The layer can be repainted, masked or deleted like any other. One undo step.
enum LightMood: String, CaseIterable, Identifiable {
    case dayToNight, nightToDay, sunset
    var id: String { rawValue }
    var title: String { switch self { case .dayToNight: "Day to night"; case .nightToDay: "Night to day"; case .sunset: "Sunset glow" } }
    var colour: CodableColor { switch self {
        case .dayToNight, .nightToDay: CodableColor(red: 0.16, green: 0.2, blue: 0.45, alpha: 1)
        case .sunset: CodableColor(red: 1, green: 0.45, blue: 0.15, alpha: 1) } }
    var blend: LayerBlend { self == .sunset ? .softLight : .multiply }
    var strength: Double { self == .sunset ? 0.75 : 0.8 }
    var fadesIn: Bool { self != .nightToDay }
}

extension Studio {
    /// Opacity of the light layer in frame `i` for the range `r`.
    static func moodOpacity(_ i: Int, range r: ClosedRange<Int>, mood: LightMood) -> Double {
        let ramp: Double
        if i <= r.lowerBound { ramp = 0 } else if i >= r.upperBound { ramp = 1 } else { ramp = fadeRamp(i - r.lowerBound, of: r.count, fadeIn: true) }
        return mood.strength * (mood.fadesIn ? ramp : 1 - ramp)
    }

    @discardableResult func addLightMood(_ mood: LightMood) -> Int {
        guard frames.count >= 2 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        checkpoint("Light mood")
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: mood.colour, width: 1)
        fill.kind = "fill"
        var layer = ArtLayer(name: L(mood.title)); layer.strokes = [fill]; layer.blend = mood.blend
        for i in frames.indices {
            var l = layer; l.opacity = Studio.moodOpacity(i, range: r, mood: mood)
            frames[i].append(l)
        }
        layers = frames[frameIndex]; selectedLayer = layers.count - 1
        changed()
        return frames.count
    }
}
