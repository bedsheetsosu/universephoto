import SwiftUI

struct TimelinePanel: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @State private var markerIndex: Int?
    @State private var markerText = ""
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.outline).frame(height: 1)
            HStack(spacing: 0) {
                trackLabel
                Rectangle().fill(theme.outline).frame(width: 1)
                frameStrip
            }
        }
        .background(theme.deep)
        .photoSurface(radius: 18)
        .alert(L("Frame marker"), isPresented: Binding(get: { markerIndex != nil }, set: { if !$0 { markerIndex = nil } })) {
            TextField(L("Name, e.g. walk"), text: $markerText)
            Button(L("OK")) { if let i = markerIndex { s.setLabel(markerText, for: i) }; markerIndex = nil }
            Button(L("Cancel"), role: .cancel) { markerIndex = nil }
        } message: { Text(L("A marker starts a section that runs to the next one. Sections can be played on their own and are exported as tags in the sprite sheet.")) }
    }
    /// Full labels when there is room, icons only (with tooltips) when the inspector makes it tight.
    private var header: some View {
        ViewThatFits(in: .horizontal) { headerRow(compact: false); headerRow(compact: true) }
    }
    private func headerRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 9 : 14) {
            HStack(spacing: 8) {
                Image(systemName: "film.stack").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.accent)
                Text(L("Timeline")).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
            }
            playbackControls
            Text(String(format: "%03d / %03d", s.frameIndex + 1, max(s.frames.count, 1)))
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary)
            Text(String(format: "%.2f s", s.animationDuration)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary.opacity(0.8)).help(L("Length including holds"))
            Spacer(minLength: 8)
            timelineToggle(L("Onion Skin"), symbol: "square.3.layers.3d", value: $s.onionSkin).help(L("Onion skinning · ⌥O"))
            OnionOptionsButton()
            if !s.markerSections.isEmpty {
                Menu { ForEach(s.markerSections, id: \.name) { sec in Button("\(sec.name)  ·  \(sec.range.lowerBound + 1)–\(sec.range.upperBound + 1)") { s.playSection(sec.name) } } }
                label: { Label(L("Sections"), systemImage: "bookmark") }.menuStyle(.borderlessButton).fixedSize().help(L("Play a marked section"))
            }
            timelineToggle(L("Loop"), symbol: "repeat", value: $s.loop).help(L("Loop"))
            timelineToggle(L("Ping-pong"), symbol: "arrow.left.arrow.right", value: $s.pingPong).help(L("Play forth and back"))
            Picker(L("Frame rate"), selection: $s.fps) {
                ForEach([6.0, 8, 12, 15, 24, 30, 60], id: \.self) { Text(LF("%d FPS", Int($0))).tag($0) }
            }
            .labelsHidden().frame(width: 80).controlSize(.small)
            .onChange(of: s.fps) { _, _ in s.stopPlayback(); s.changed() }
            Rectangle().fill(theme.outline).frame(width: 1, height: 17)
            Button { s.blankFrame() } label: { Label(L("Blank"), systemImage: "plus") }
                .buttonStyle(PhotoButtonStyle()).help(L("Blank"))
            Button { s.addFrame() } label: { Label(L("Duplicate"), systemImage: "square.on.square") }
                .buttonStyle(PhotoButtonStyle()).help(L("Duplicate frame · ⇧F"))
            Button { s.removeFrame() } label: { Image(systemName: "trash") }
                .buttonStyle(PhotoButtonStyle()).disabled(s.frames.count < 2).help(L("Delete frame")).accessibilityLabel(L("Delete frame"))
        }
        .font(.system(size: 10, weight: .medium)).lineLimit(1).padding(.horizontal, 16).frame(height: 47)
        .modifier(CompactLabels(compact: compact))
    }
    private var playbackControls: some View {
        HStack(spacing: 1) {
            Button { s.stepToFrame(max(0, s.frameIndex - 1)) } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 9)).frame(width: 28, height: 26)
            }.help(L("Previous frame · ⌥←")).accessibilityLabel(L("Previous frame"))
            Button { s.togglePlayback() } label: {
                Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.accent).frame(width: 31, height: 26)
            }.disabled(s.frames.count < 2).help(L("Play or pause · Space")).accessibilityLabel(L(s.isPlaying ? "Pause" : "Play"))
            Button { s.stepToFrame(min(s.frames.count - 1, s.frameIndex + 1)) } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 9)).frame(width: 28, height: 26)
            }.help(L("Next frame · ⌥→")).accessibilityLabel(L("Next frame"))
        }
        .buttonStyle(PhotoPress()).foregroundStyle(theme.text)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.outline))
    }
    private func timelineToggle(_ title: String, symbol: String, value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium))
                .foregroundStyle(value.wrappedValue ? theme.accent : theme.secondary)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(value.wrappedValue ? theme.accentSoft : theme.card, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(value.wrappedValue ? theme.accent.opacity(0.25) : theme.outline))
        }.buttonStyle(PhotoPress())
    }
    private var trackLabel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("DRAWINGS")).font(.system(size: 8, weight: .semibold)).tracking(1.5).foregroundStyle(theme.secondary)
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 13)).foregroundStyle(theme.accent)
                Text(s.activeLayer?.name ?? L("Drawing layer")).font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(theme.text)
                if s.activeLayer?.allFrames == true { Image(systemName: "film.stack.fill").font(.system(size: 10)).foregroundStyle(theme.accent).help(L("Same in all frames")) }
            }
            Text(L("Frame snapshots"))
                .font(.system(size: 9)).foregroundStyle(theme.secondary.opacity(0.75))
            if let a = s.audio { SoundTrackRow(track: a) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 15).frame(width: 165, alignment: .leading)
    }
    private var frameStrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 9) {
                    if s.frames.isEmpty {
                        Button { s.addFrame() } label: {
                            VStack(spacing: 8) {
                                Text("01").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary)
                                RoundedRectangle(cornerRadius: 8).strokeBorder(theme.outline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .frame(width: 88, height: 59)
                                    .overlay(Image(systemName: "plus").font(.system(size: 17, weight: .light)).foregroundStyle(theme.accent))
                            }
                        }.buttonStyle(PhotoPress()).help(L("Start animation with a second frame"))
                    }
                    ForEach(Array(s.frames.enumerated()), id: \.offset) { index, layers in
                        frameCell(index: index, layers: layers).id(index)
                    }
                }.padding(.horizontal, 15).padding(.top, 11).padding(.bottom, s.audio != nil ? 24 : 11)
            }
            .onChange(of: s.frameIndex) { _, index in
                withAnimation(.easeInOut(duration: 0.15)) { reader.scrollTo(index, anchor: .center) }
            }
        }
    }
    private func frameCell(index: Int, layers: [ArtLayer]) -> some View {
        let selected = index == s.frameIndex
        return Button { s.stepToFrame(index) } label: {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(selected ? theme.accent : .clear).frame(width: 4, height: 4)
                    Text(String(format: "%02d", index + 1)).font(.system(size: 9, weight: selected ? .semibold : .regular, design: .monospaced))
                    if s.hold(index) > 1 { Text("×\(s.hold(index))").font(.system(size: 8, weight: .semibold, design: .rounded)).padding(.horizontal, 4).padding(.vertical, 1).background(theme.accentSoft, in: Capsule()).foregroundStyle(theme.accent) }
                }.foregroundStyle(selected ? theme.accent : theme.secondary)
                FrameThumbnail(layers: s.composite(selected ? s.layers : layers), width: s.width, height: s.height)
                    .frame(width: 82, height: 53).padding(3)
                    .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 7))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.outline), lineWidth: selected ? 2 : 1))
                    .shadow(color: selected ? theme.accent.opacity(0.15) : .clear, radius: 6, y: 2)
                    .opacity(s.inPlayRange(index) ? 1 : 0.4)
                    .overlay(alignment: .bottom) { if s.audio != nil { FrameWaveform(index: index).frame(width: 82, height: 12).offset(y: 18) } }
                    .overlay(alignment: .topLeading) { if !s.label(index).isEmpty { Text(s.label(index)).font(.system(size: 8, weight: .semibold, design: .rounded)).lineLimit(1).padding(.horizontal, 5).padding(.vertical, 1.5).background(theme.accentGradient, in: Capsule()).foregroundStyle(theme.onAccent).frame(maxWidth: 80, alignment: .leading).offset(x: -3, y: -6).help(L("Marker")) } }
                    .overlay(alignment: .topTrailing) { if s.referenceFrame == index { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.white).padding(3).background(Color(cgColor: Studio.referenceColor), in: Circle()).offset(x: 4, y: -4).help(L("Reference frame")) } }
                    .overlay(alignment: .bottom) { if let r = Playback.clamp(s.playRange, count: s.frames.count), r.lowerBound == index || r.upperBound == index { Capsule().fill(theme.accent).frame(width: 30, height: 3).offset(y: 5) } }
            }
        }.buttonStyle(PhotoPress()).help(LF("Frame %d", index + 1)).accessibilityLabel(LF("Frame %d", index + 1))
        .contextMenu {
            Menu(L("Hold")) { ForEach(Studio.holdChoices, id: \.self) { n in Button { s.setHold(n, for: index) } label: { if s.hold(index) == n { Label(LF("%d frames", n), systemImage: "checkmark") } else { Text(LF("%d frames", n)) } } } }
            Button(s.label(index).isEmpty ? L("Add marker…") : L("Rename marker…")) { markerText = s.label(index); markerIndex = index }
            if !s.label(index).isEmpty { Button(L("Remove marker")) { s.setLabel("", for: index) } }
            Divider()
            Button(L("Copy frame")) { s.copyFrame(index) }
            Button(L("Paste frame after")) { s.pasteFrame(after: index) }.disabled(s.frameClipboard == nil)
            Button(s.referenceFrame == index ? L("Unpin reference") : L("Pin as reference")) { s.toggleReference(index) }
            Divider()
            Menu(L("Tween to next frame")) {
                ForEach(Studio.tweenChoices, id: \.self) { n in Button(LF("%d frames", n)) { s.tweenToNext(from: index, count: n, eased: false) } }
                Menu(L("Eased")) { ForEach(Studio.tweenChoices, id: \.self) { n in Button(LF("%d frames", n)) { s.tweenToNext(from: index, count: n, eased: true) } } }
            }.disabled(index >= s.frames.count - 1)
            Divider()
            Button(L("Play from here")) { s.setPlayStart(index) }
            Button(L("Play up to here")) { s.setPlayEnd(index) }
            Button(L("Play all frames")) { s.playRange = nil }.disabled(s.playRange == nil)
            Divider()
            Button(L("Move frame left")) { s.moveFrame(from: index, to: index - 1) }.disabled(index == 0)
            Button(L("Move frame right")) { s.moveFrame(from: index, to: index + 1) }.disabled(index >= s.frames.count - 1)
        }
        .draggable("frame:\(index)")
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first, item.hasPrefix("frame:"), let from = Int(item.dropFirst(6)) else { return false }
            s.moveFrame(from: from, to: index); return true
        }
    }
}
struct FrameThumbnail: View {
    var layers: [ArtLayer]; var width: Int; var height: Int
    @State private var thumbnail: CGImage?
    var body: some View {
        Group { if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().scaledToFit() } else { Color.clear } }
            .task(id: layers) {
                let l = layers, w = width, h = height
                let result = await Task.detached(priority: .utility) { Renderer.render(layers: l, width: w, height: h) }.value
                guard !Task.isCancelled else { return }
                thumbnail = result
            }
    }
}

/// The small menu next to the onion-skin toggle: frames before/after, opacity, colours.
struct OnionOptionsButton: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @AppStorage("onionBefore") private var before = 1
    @AppStorage("onionAfter") private var after = 0
    @AppStorage("onionOpacity") private var opacity = 0.25
    @AppStorage("onionTinted") private var tinted = true
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: { Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).frame(width: 18, height: 24) }
            .buttonStyle(PhotoPress()).foregroundStyle(theme.secondary).help(L("Onion skin options")).accessibilityLabel(L("Onion skin options"))
            .popover(isPresented: $open, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Onion skin")).font(.system(size: 12, weight: .semibold))
                    Stepper(LF("Before: %d", before), value: $before, in: 0...5)
                    Stepper(LF("After: %d", after), value: $after, in: 0...5)
                    HStack { Text(L("Opacity")); Slider(value: $opacity, in: 0.05...0.8); Text("\(Int(opacity * 100)) %").monospacedDigit().frame(width: 38, alignment: .trailing) }
                    Toggle(L("Tint: before red, after green"), isOn: $tinted)
                }
                .font(.system(size: 11)).padding(14).frame(width: 260)
                .onChange(of: [Double(before), Double(after), opacity, tinted ? 1 : 0]) { _, _ in s.objectWillChange.send() }
            }
    }
}

private struct CompactLabels: ViewModifier {
    var compact: Bool
    func body(content: Content) -> some View {
        if compact { content.labelStyle(.iconOnly) } else { content.labelStyle(.titleAndIcon) }
    }
}

/// The bit of sound under one frame, as a small mirrored waveform.
struct FrameWaveform: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    let index: Int
    var body: some View {
        let cache = s.audioEngine.cache(for: s.audio)
        let t0 = s.soundTime(frame: index), t1 = t0 + Double(s.hold(index)) / max(1, s.fps)
        let peaks = cache.map { t1 > 0 ? $0.peaks(from: max(0, t0), to: t1, buckets: 20) : [] } ?? []
        Canvas { ctx, size in
            guard !peaks.isEmpty else { return }
            let w = size.width / CGFloat(peaks.count)
            for (i, p) in peaks.enumerated() {
                let h = max(1, CGFloat(p) * size.height)
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * w + w * 0.2, y: (size.height - h) / 2, width: w * 0.6, height: h), cornerRadius: 1), with: .color(theme.accent.opacity(0.75)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Name of the sound plus its options (start frame, volume, snippets while stepping).
struct SoundTrackRow: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @AppStorage("audioScrub") private var scrub = true
    @State private var open = false
    let track: AudioTrack
    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform").foregroundStyle(theme.accent)
                Text(track.name).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold)).foregroundStyle(theme.secondary)
            }.font(.system(size: 10, weight: .medium))
        }
        .buttonStyle(PhotoPress()).help(L("Sound options"))
        .popover(isPresented: $open, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(track.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Stepper(LF("Starts at frame %d", track.startFrame + 1), value: Binding(get: { track.startFrame }, set: { s.setAudioStart($0) }), in: 0...max(0, s.frames.count - 1))
                Button(L("Start at the current frame")) { s.setAudioStart(s.frameIndex) }
                HStack { Text(L("Volume")); Slider(value: Binding(get: { track.volume }, set: { s.setAudioVolume($0) }), in: 0...1) }
                Toggle(L("Play a snippet when stepping through frames"), isOn: $scrub)
                Divider()
                Button(L("Remove sound"), role: .destructive) { open = false; s.removeAudio() }
            }
            .font(.system(size: 11)).padding(14).frame(width: 270)
        }
    }
}
