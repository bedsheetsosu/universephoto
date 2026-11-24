import SwiftUI
import TafelKit

/// The live palette picture from the Mac and where its window sits. Separate from ClientModel so
/// its up to 10 pictures per second only redraw the palette window, not the whole app.
@MainActor
final class PaletteState: ObservableObject {
    @Published var image: UIImage?
    /// Window centre, 0…1 of the screen.
    @Published var center: CGPoint {
        didSet { UserDefaults.standard.set([center.x, center.y], forKey: "paletteCenter") }
    }
    @Published var width: CGFloat {
        didSet { UserDefaults.standard.set(Double(width), forKey: "paletteWidth") }
    }
    @Published var collapsed = false

    static let widthRange: ClosedRange<CGFloat> = 140...640

    init() {
        let c = UserDefaults.standard.array(forKey: "paletteCenter") as? [Double]
        center = c.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } ?? CGPoint(x: 0.85, y: 0.32)
        let w = UserDefaults.standard.double(forKey: "paletteWidth")
        width = w > 0 ? CGFloat(w) : 260
    }

    /// Called on any thread with the JPEG from the Mac (empty = palette removed).
    nonisolated func receive(_ jpeg: Data) {
        guard !jpeg.isEmpty else {
            Task { @MainActor in self.image = nil }
            return
        }
        guard let img = UIImage(data: jpeg)?.preparingForDisplay() else { return }
        Task { @MainActor in self.image = img }
    }
}

struct PaletteOverlay: View {
    @ObservedObject var palette: PaletteState
    let send: (MouseEvent) -> Void
    let close: () -> Void
    @State private var moveStart: CGPoint?
    @State private var widthStart: CGFloat?
    @State private var pressing = false

    var body: some View {
        GeometryReader { geo in
            if let img = palette.image, img.size.width > 0 {
                let w = palette.width
                let h = w * img.size.height / img.size.width
                VStack(spacing: 0) {
                    titleBar(in: geo.size)
                    if !palette.collapsed {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: w, height: h)
                            .contentShape(Rectangle())
                            .gesture(touch(size: CGSize(width: w, height: h)))
                            .overlay(alignment: .bottomTrailing) { resizeHandle }
                            .accessibilityLabel(L("Palette vom Mac"))
                            .accessibilityAddTraits(.allowsDirectInteraction)
                    }
                }
                .frame(width: w)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .position(x: palette.center.x * geo.size.width, y: palette.center.y * geo.size.height)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(Brand.spring, value: palette.image == nil)
        .animation(Brand.spring, value: palette.collapsed)
    }

    private func titleBar(in screen: CGSize) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(.white.opacity(0.45)).frame(width: 28, height: 4)
            Spacer()
            Button {
                palette.collapsed.toggle()
            } label: {
                Image(systemName: palette.collapsed ? "chevron.down" : "chevron.up").font(.caption.bold())
            }
            .accessibilityLabel(palette.collapsed ? L("Palette aufklappen") : L("Palette einklappen"))
            Button(action: close) {
                Image(systemName: "xmark").font(.caption.bold())
            }
            .accessibilityLabel(L("Palette entfernen"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { v in
                    let start = moveStart ?? palette.center
                    moveStart = start
                    palette.center = CGPoint(
                        x: min(max(start.x + v.translation.width / max(screen.width, 1), 0.05), 0.95),
                        y: min(max(start.y + v.translation.height / max(screen.height, 1), 0.05), 0.95))
                }
                .onEnded { _ in moveStart = nil }
        )
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 26, height: 26)
            .background(.black.opacity(0.35), in: Circle())
            .padding(4)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { v in
                        let start = widthStart ?? palette.width
                        widthStart = start
                        palette.width = min(max(start + v.translation.width, PaletteState.widthRange.lowerBound), PaletteState.widthRange.upperBound)
                    }
                    .onEnded { _ in widthStart = nil }
            )
            .accessibilityHidden(true)
    }

    /// Finger or Pencil on the picture → mouse down/drag/up at the same spot on the Mac.
    private func touch(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let x = Float(min(max(v.location.x / max(size.width, 1), 0), 1))
                let y = Float(min(max(v.location.y / max(size.height, 1), 0), 1))
                send(MouseEvent(phase: pressing ? .move : .down, x: x, y: y))
                pressing = true
            }
            .onEnded { v in
                let x = Float(min(max(v.location.x / max(size.width, 1), 0), 1))
                let y = Float(min(max(v.location.y / max(size.height, 1), 0), 1))
                send(MouseEvent(phase: .up, x: x, y: y))
                pressing = false
            }
    }
}
