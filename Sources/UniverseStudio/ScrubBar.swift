import SwiftUI

/// Animate (0.93): a time ruler over the frame strip covering the whole animation. Dragging on it
/// scrubs through the frames (with sound snippets), and it shows seconds, the play range, markers
/// and the playhead – handy once the strip is longer than the window.
enum Scrub {
    /// Frame under `fraction` (0…1) of the whole length, holds included.
    static func frame(at fraction: Double, holds: [Int]) -> Int {
        let total = holds.reduce(0) { $0 + max(1, $1) }
        guard total > 0 else { return 0 }
        let tick = min(total - 1, max(0, Int(fraction * Double(total))))
        var acc = 0
        for (i, h) in holds.enumerated() { acc += max(1, h); if tick < acc { return i } }
        return holds.count - 1
    }

    /// Start and end (0…1) of frame `i`.
    static func span(of i: Int, holds: [Int]) -> (Double, Double) {
        let total = Double(holds.reduce(0) { $0 + max(1, $1) })
        guard total > 0, holds.indices.contains(i) else { return (0, 0) }
        let before = Double(holds[..<i].reduce(0) { $0 + max(1, $1) })
        return (before / total, (before + Double(max(1, holds[i]))) / total)
    }
}

struct ScrubBar: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @State private var lastFrame: Int?

    var body: some View {
        let holds = (0..<max(1, s.frames.count)).map { s.hold($0) }
        let seconds = s.animationDuration
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(theme.card.opacity(0.6))
                if let r = Playback.clamp(s.playRange, count: s.frames.count) {
                    let a = Scrub.span(of: r.lowerBound, holds: holds).0, b = Scrub.span(of: r.upperBound, holds: holds).1
                    Rectangle().fill(theme.accent.opacity(0.16)).frame(width: (b - a) * w).offset(x: a * w)
                }
                // Whole seconds.
                ForEach(0..<max(0, Int(seconds) + 1), id: \.self) { sec in
                    let x = seconds > 0 ? Double(sec) / seconds * w : 0
                    Rectangle().fill(theme.secondary.opacity(0.4)).frame(width: 1, height: 6).offset(x: x, y: 12)
                    if seconds <= 30 || sec % 5 == 0 { Text("\(sec)s").font(.system(size: 7, weight: .medium).monospacedDigit()).foregroundStyle(theme.secondary.opacity(0.8)).offset(x: x + 2, y: 1) }
                }
                ForEach(s.markerSections, id: \.name) { sec in
                    Rectangle().fill(theme.accent).frame(width: 2, height: 18).offset(x: Scrub.span(of: sec.range.lowerBound, holds: holds).0 * w)
                }
                let head = Scrub.span(of: s.frameIndex, holds: holds)
                RoundedRectangle(cornerRadius: 2).fill(theme.accentGradient).frame(width: max(3, (head.1 - head.0) * w), height: 18).offset(x: head.0 * w).opacity(0.85)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard s.frames.count > 1 else { return }
                let i = Scrub.frame(at: Double(g.location.x / max(1, w)), holds: holds)
                if i != lastFrame { lastFrame = i; s.stepToFrame(i) }
            }.onEnded { _ in lastFrame = nil })
        }
        .frame(height: 18)
        .accessibilityElement().accessibilityLabel(L("Time ruler")).accessibilityValue(LF("Frame %d", s.frameIndex + 1))
        .help(L("Drag to scrub through the animation"))
    }
}
