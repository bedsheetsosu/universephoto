import Foundation
import CoreGraphics

/// Animation → Effects → Floating symbols (0.231): little symbols drift up from the top of the active
/// layer, sway a little and fade – hearts for love, notes for music, Z's for sleep, question marks
/// for confusion. One after another, as a seamless loop over the play range (or all frames),
/// following the layer if it moves. On a new layer above it. One undo step. Returns how many there
/// are at a time.
enum FloatingSymbol: String, CaseIterable, Identifiable {
    case hearts, notes, sleep, question
    var id: String { rawValue }
    var title: String { switch self { case .hearts: "Hearts"; case .notes: "Music notes"; case .sleep: "Sleepy Z's"; case .question: "Question marks" } }
    var glyphs: [String] { switch self { case .hearts: ["♥"]; case .notes: ["♪", "♫"]; case .sleep: ["Z", "z"]; case .question: ["?"] } }
    var colour: CodableColor { switch self {
        case .hearts: CodableColor(red: 0.93, green: 0.25, blue: 0.4, alpha: 1)
        case .notes: CodableColor(red: 0.25, green: 0.3, blue: 0.55, alpha: 1)
        case .sleep: CodableColor(red: 0.45, green: 0.55, blue: 0.85, alpha: 1)
        case .question: CodableColor(red: 0.95, green: 0.6, blue: 0.1, alpha: 1) } }
}

extension Studio {
    /// Symbol `c` of `total` in frame `k` of `n`: (rise 0…1, sideways sway −1…1, opacity), nil = not shown.
    static func symbolState(_ c: Int, of total: Int, frame k: Int, count n: Int) -> (rise: Double, sway: Double, alpha: Double)? {
        guard n > 0, total > 0 else { return nil }
        let a = Double(k) / Double(n) + Double(c) / Double(total)
        let t = a - a.rounded(.down)                        // its own age, wrapping round: a loop
        guard t > 0.02 else { return nil }
        let alpha = min(1, t * 5) * (t > 0.7 ? (1 - t) / 0.3 : 1)
        return (t, sin(t * 2 * .pi * 1.5 + Double(c)), alpha)
    }

    @discardableResult func addFloatingSymbols(_ kind: FloatingSymbol, count: Int = 3) -> Int {
        guard frames.count >= 2, count > 0, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let size = max(12, min(local.width, local.height) * 0.35), climb = max(40, local.height * 1.2)
        checkpoint("Floating symbols")
        let layer = ArtLayer(name: L(kind.title))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let top = CGPoint(x: local.midX, y: local.minY).applying(matrix(s.transform))
                l.strokes = (0..<count).compactMap { c in
                    guard let st = Studio.symbolState(c, of: count, frame: i - r.lowerBound, count: r.count) else { return nil }
                    let side = (Double(c % 3) - 1) * size * 0.9            // three lanes: left, middle, right
                    var colour = kind.colour; colour.alpha = st.alpha
                    let glyphSize = size * (0.7 + 0.4 * st.rise)
                    var g = InkStroke(points: [InkPoint(x: top.x + side + st.sway * size * 0.4, y: top.y - climb * st.rise - glyphSize, pressure: 1)],
                                      color: colour, width: glyphSize)
                    g.kind = "text"; g.text = kind.glyphs[c % kind.glyphs.count]; g.fontName = "Helvetica-Bold"; g.textAlign = "center"
                    return g
                }
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return count
    }
}
