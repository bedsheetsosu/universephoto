import Foundation

/// Animation → Typewriter (0.102): the text on the active layer appears letter by letter or word
/// by word over new frames (several text boxes one after another), then stays for a moment.
enum Typewriter {
    /// Visible character counts per step: letters (`perStep` at a time) or whole words.
    static func steps(_ text: String, byWord: Bool, perStep: Int = 1) -> [Int] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }
        if byWord {
            var ends: [Int] = []
            for (i, c) in chars.enumerated() where !c.isWhitespace && (i + 1 == chars.count || chars[i + 1].isWhitespace) { ends.append(i + 1) }
            return ends
        }
        return Array(stride(from: perStep, through: chars.count, by: perStep)) + (chars.count % perStep == 0 ? [] : [chars.count])
    }
}

extension Studio {
    /// Replaces the current frame with the typing frames (last one held for `restTicks`).
    @discardableResult func typewriter(byWord: Bool, perStep: Int = 1, restTicks: Int = 12) -> Int {
        guard let layer = activeLayer else { return 0 }
        let texts = layer.strokes.indices.filter { layer.strokes[$0].kind == "text" && !(layer.strokes[$0].text ?? "").isEmpty }
        guard !texts.isEmpty else { return 0 }
        // Steps over all text boxes in drawing order: (box, visible characters).
        var plan: [(Int, Int)] = []
        for i in texts { plan += Typewriter.steps(layer.strokes[i].text ?? "", byWord: byWord, perStep: perStep).map { (i, $0) } }
        guard plan.count > 1 else { return 0 }
        stopPlayback(); checkpoint("Typewriter")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let source = frames[frameIndex], id = layer.id
        let made: [[ArtLayer]] = plan.map { box, n in
            source.map { l in
                guard l.id == id else { return l }
                var m = l
                for i in texts {
                    let full = l.strokes[i].text ?? ""
                    m.strokes[i].text = i < box ? full : i == box ? String(full.prefix(n)) : ""
                }
                m.strokes = m.strokes.filter { $0.kind != "text" || !($0.text ?? "").isEmpty }
                return m
            }
        }
        frames[frameIndex] = made[0]
        metaInsert(at: frameIndex + 1, holds: Array(repeating: 1, count: made.count - 2) + [max(1, restTicks)])
        frames.insert(contentsOf: made.dropFirst(), at: frameIndex + 1)
        layers = frames[frameIndex]
        changed()
        return made.count
    }
}
