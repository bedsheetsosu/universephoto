import Foundation

/// Animate → right-click a frame → Tween to next frame: inserts in-between frames that move,
/// scale, rotate and fade each layer from this frame's state to the next one's (matched by layer;
/// drawings come from this frame). Linear or eased in and out.
enum Tween {
    static func ease(_ t: Double, eased: Bool) -> Double { eased ? t * t * (3 - 2 * t) : t }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// Rotation the short way round (350° → 10° passes 0°).
    static func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        return a + d * t
    }

    static func blend(_ a: LayerTransform, _ b: LayerTransform, _ t: Double) -> LayerTransform {
        LayerTransform(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t), scale: lerp(a.scale, b.scale, t), rotation: lerpAngle(a.rotation, b.rotation, t))
    }

    /// `count` frames between `from` and `to`.
    static func frames(from: [ArtLayer], to: [ArtLayer], count: Int, eased: Bool, morph: Bool = false) -> [[ArtLayer]] {
        guard count > 0 else { return [] }
        let target = Dictionary(to.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return (1...count).map { k in
            let t = ease(Double(k) / Double(count + 1), eased: eased)
            return from.map { layer in
                guard let end = target[layer.id] else { return layer }
                var l = layer
                l.transform = blend(layer.transform, end.transform, t)
                l.opacity = lerp(layer.opacity, end.opacity, t)
                if morph, let blended = StrokeMorph.strokes(layer.strokes, end.strokes, t) { l.strokes = blended }
                return l
            }
        }
    }
}

extension Studio {
    static let tweenChoices = [1, 2, 3, 4, 6, 8, 12]

    /// Inserts in-betweens after frame `index` towards the next frame. Returns how many.
    @discardableResult func tweenToNext(from index: Int, count: Int, eased: Bool, morph: Bool = false) -> Int {
        guard frames.indices.contains(index), frames.indices.contains(index + 1), count > 0 else { return 0 }
        stopPlayback(); checkpoint("Tween")
        frames[frameIndex] = layers
        let made = Tween.frames(from: frames[index], to: frames[index + 1], count: count, eased: eased, morph: morph)
        metaInsert(at: index + 1, holds: Array(repeating: 1, count: made.count))
        frames.insert(contentsOf: made, at: index + 1)
        if frameIndex > index { frameIndex += made.count }
        layers = frames[frameIndex]
        changed()
        return made.count
    }
}

extension Studio {
    /// Animation → Close loop (0.113): in-betweens after the last frame back towards the first, so
    /// a looping animation runs on without a jump. Position, size, turn and opacity glide; strokes
    /// morph when both frames have matching strokes. Returns how many frames were added.
    @discardableResult func closeLoop(count: Int, eased: Bool = true) -> Int {
        guard frames.count > 1, count > 0 else { return 0 }
        stopPlayback(); checkpoint("Close loop")
        frames[frameIndex] = layers
        let made = Tween.frames(from: frames[frames.count - 1], to: frames[0], count: count, eased: eased, morph: true)
        metaInsert(at: frames.count, holds: Array(repeating: 1, count: made.count))
        frames.append(contentsOf: made)
        layers = frames[frameIndex]
        changed()
        return made.count
    }
}
