import SwiftUI

struct TimelinePanel: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
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
    }
    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "film.stack").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.accent)
                Text(L("Timeline")).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
            }
            playbackControls
            Text(String(format: "%03d / %03d", s.frameIndex + 1, max(s.frames.count, 1)))
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary)
            Spacer(minLength: 8)
            timelineToggle(L("Onion Skin"), symbol: "square.3.layers.3d", value: $s.onionSkin).help(L("Onion skinning · ⌥O"))
            timelineToggle(L("Loop"), symbol: "repeat", value: $s.loop)
            Picker(L("Frame rate"), selection: $s.fps) {
                ForEach([6.0, 8, 12, 15, 24, 30, 60], id: \.self) { Text(LF("%d FPS", Int($0))).tag($0) }
            }
            .labelsHidden().frame(width: 80).controlSize(.small)
            .onChange(of: s.fps) { _, _ in s.stopPlayback(); s.changed() }
            Rectangle().fill(theme.outline).frame(width: 1, height: 17)
            Button { s.blankFrame() } label: { Label(L("Blank"), systemImage: "plus") }
                .buttonStyle(PhotoButtonStyle())
            Button { s.addFrame() } label: { Label(L("Duplicate"), systemImage: "square.on.square") }
                .buttonStyle(PhotoButtonStyle()).help(L("Duplicate frame · ⇧F"))
            Button { s.removeFrame() } label: { Image(systemName: "trash") }
                .buttonStyle(PhotoButtonStyle()).disabled(s.frames.count < 2).help(L("Delete frame")).accessibilityLabel(L("Delete frame"))
        }
        .font(.system(size: 10, weight: .medium)).padding(.horizontal, 16).frame(height: 47)
    }
    private var playbackControls: some View {
        HStack(spacing: 1) {
            Button { s.selectFrame(max(0, s.frameIndex - 1)) } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 9)).frame(width: 28, height: 26)
            }.help(L("Previous frame · ⌥←")).accessibilityLabel(L("Previous frame"))
            Button { s.togglePlayback() } label: {
                Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.accent).frame(width: 31, height: 26)
            }.disabled(s.frames.count < 2).help(L("Play or pause · Space")).accessibilityLabel(L(s.isPlaying ? "Pause" : "Play"))
            Button { s.selectFrame(min(s.frames.count - 1, s.frameIndex + 1)) } label: {
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
            }
            Text(L("Frame snapshots"))
                .font(.system(size: 9)).foregroundStyle(theme.secondary.opacity(0.75))
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
                }.padding(.horizontal, 15).padding(.vertical, 11)
            }
            .onChange(of: s.frameIndex) { _, index in
                withAnimation(.easeInOut(duration: 0.15)) { reader.scrollTo(index, anchor: .center) }
            }
        }
    }
    private func frameCell(index: Int, layers: [ArtLayer]) -> some View {
        let selected = index == s.frameIndex
        return Button { s.stopPlayback(); s.selectFrame(index) } label: {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(selected ? theme.accent : .clear).frame(width: 4, height: 4)
                    Text(String(format: "%02d", index + 1)).font(.system(size: 9, weight: selected ? .semibold : .regular, design: .monospaced))
                }.foregroundStyle(selected ? theme.accent : theme.secondary)
                FrameThumbnail(layers: s.composite(selected ? s.layers : layers), width: s.width, height: s.height)
                    .frame(width: 82, height: 53).padding(3)
                    .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 7))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.outline), lineWidth: selected ? 2 : 1))
                    .shadow(color: selected ? theme.accent.opacity(0.15) : .clear, radius: 6, y: 2)
            }
        }.buttonStyle(PhotoPress()).help(LF("Frame %d", index + 1)).accessibilityLabel(LF("Frame %d", index + 1))
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
