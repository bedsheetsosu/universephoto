import SwiftUI

/// Animation → Preview window: plays the animation from pre-rendered frames at its real speed
/// (holds, play range, ping-pong and loop included) in its own window, without touching the
/// document – smooth even for heavy frames, and it can sit on a second screen while you draw.
enum AnimationPreview {
    static let windowID = "animationPreview"

    /// Frame index per tick for one full cycle.
    static func sequence(count: Int, range: ClosedRange<Int>?, pingPong: Bool, hold: (Int) -> Int) -> [Int] {
        guard count > 0 else { return [] }
        let r = Playback.clamp(range, count: count) ?? 0...(count - 1)
        var order = Array(r)
        if pingPong && r.count > 2 { order += Array(r.dropFirst().dropLast().reversed()) }
        else if pingPong && r.count == 2 { order = [r.lowerBound, r.upperBound] }
        return order.flatMap { Array(repeating: $0, count: max(1, hold($0))) }
    }

    /// Tick at `elapsed` seconds; nil once a non-looping run has ended (shows the last frame).
    static func tick(elapsed: Double, fps: Double, length: Int, loop: Bool) -> Int? {
        guard length > 0 else { return nil }
        let t = max(0, Int(elapsed * max(1, fps)))
        if loop { return t % length }
        return t < length ? t : nil
    }
}

struct AnimationPreviewWindow: View {
    @EnvironmentObject var s: Studio
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("photoAccent") private var accent = "mint"
    @AppStorage("previewChecker") private var checker = false
    @Environment(\.colorScheme) private var systemScheme
    @State private var images: [CGImage] = []
    @State private var start = Date()
    @State private var playing = true
    @State private var pausedTick = 0

    var body: some View {
        let theme = FocusMode.theme(appearance: appearance, accent: accent, systemDark: systemScheme == .dark)
        let seq = AnimationPreview.sequence(count: images.count, range: s.playRange, pingPong: s.pingPong, hold: { s.hold($0) })
        VStack(spacing: 0) {
            TimelineView(.animation(paused: !playing)) { context in
                let tick = playing ? AnimationPreview.tick(elapsed: context.date.timeIntervalSince(start), fps: s.fps, length: seq.count, loop: s.loop) ?? max(0, seq.count - 1) : pausedTick
                let frame = seq.indices.contains(tick) ? seq[tick] : 0
                ZStack {
                    if checker { Checkerboard() } else { Color.white }
                    if images.indices.contains(frame) { Image(decorative: images[frame], scale: 1).resizable().interpolation(.medium).scaledToFit() }
                    else { ProgressView().controlSize(.small) }
                }
                .aspectRatio(CGSize(width: max(1, s.width), height: max(1, s.height)), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
                .overlay(alignment: .bottomLeading) {
                    Text(String(format: "%02d", frame + 1)).font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 3).background(.black.opacity(0.45), in: Capsule()).foregroundStyle(.white).padding(20)
                }
                .onChange(of: playing) { _, now in
                    if !now { pausedTick = tick } else { start = Date().addingTimeInterval(-Double(pausedTick) / max(1, s.fps)) }
                }
            }
            HStack(spacing: 10) {
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 22) }
                    .help(L("Play or pause")).accessibilityLabel(L(playing ? "Pause" : "Play"))
                Button { start = Date(); pausedTick = 0 } label: { Image(systemName: "backward.end.fill") }
                    .help(L("From the start")).accessibilityLabel(L("From the start"))
                Text(LF("%d FPS", Int(s.fps))).monospacedDigit().foregroundStyle(theme.secondary)
                Spacer()
                Toggle(L("Transparency grid"), isOn: $checker).toggleStyle(.switch).controlSize(.mini)
            }
            .buttonStyle(PhotoPress()).font(.system(size: 11, weight: .medium)).padding(.horizontal, 14).frame(height: 38)
        }
        .frame(minWidth: 320, minHeight: 260)
        .background(PhotoAmbient())
        .foregroundStyle(theme.text)
        .environment(\.photoTheme, theme)
        .tint(theme.accent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .task(id: renderKey) { await render() }
    }

    private var renderKey: String { "\(s.undoStack.count)-\(s.tabs.count)-\(s.frames.count)-\(s.width)x\(s.height)-\(s.frameIndex)" }

    private func render() async {
        let d = s.document()
        let frames = (d.frames.isEmpty ? [d.layers] : d.frames).map { s.composite($0) }
        let w = d.width, h = d.height
        let target = 1200.0 / Double(max(w, h))
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let out = await Task.detached(priority: .userInitiated) { () -> [CGImage] in
            frames.compactMap { f in Renderer.render(layers: f, width: w, height: h).flatMap { ImageFiles.scaled($0, by: min(1, target)) } }
        }.value
        if !Task.isCancelled, out.count == frames.count { images = out }
    }
}

struct AnimationPreviewButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(L("Preview window")) { openWindow(id: AnimationPreview.windowID) }.keyboardShortcut("p", modifiers: [.command, .option])
    }
}
