import SwiftUI
import PhotosUI
import UIKit
import TafelKit

/// A photo that floats over the picture on the iPad only (it never goes to the Mac), for drawing
/// from a reference or tracing. Unlocked: drag to move, pinch to scale. Locked: Pencil and fingers
/// pass straight through to the Mac, only the small lock button stays touchable.
@MainActor
final class ReferenceImage: ObservableObject {
    @Published private(set) var image: UIImage?
    /// Centre in screen fractions (0…1).
    @Published var center = CGPoint(x: 0.78, y: 0.3) { didSet { saveLayout() } }
    /// Width as a fraction of the screen width.
    @Published var width: CGFloat = 0.3 { didSet { saveLayout() } }
    @Published var opacity: Double = 0.85 { didSet { saveLayout() } }
    @Published var locked = false { didSet { saveLayout() } }
    @Published var flipped = false { didSet { saveLayout() } }
    @Published var gray = false { didSet { saveLayout() } }
    @Published var pickerShown = false

    private static let layoutKey = "referenceLayout"
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("reference.jpg")
    }
    private var loading = true

    init() {
        if let d = UserDefaults.standard.dictionary(forKey: Self.layoutKey) {
            center = CGPoint(x: d["x"] as? Double ?? 0.78, y: d["y"] as? Double ?? 0.3)
            width = d["w"] as? Double ?? 0.3
            opacity = d["o"] as? Double ?? 0.85
            locked = d["l"] as? Bool ?? false
            flipped = d["f"] as? Bool ?? false
            gray = d["g"] as? Bool ?? false
        }
        if let data = try? Data(contentsOf: Self.fileURL) { image = UIImage(data: data) }
        loading = false
    }

    func set(_ img: UIImage) {
        let small = Self.downscaled(img, maxSide: 2048)
        image = small
        locked = false
        try? small.jpegData(compressionQuality: 0.9)?.write(to: Self.fileURL, options: .atomic)
    }

    func clear() {
        image = nil
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    private func saveLayout() {
        guard !loading else { return }
        UserDefaults.standard.set(["x": center.x, "y": center.y, "w": width, "o": opacity, "l": locked, "f": flipped, "g": gray], forKey: Self.layoutKey)
    }

    private static func downscaled(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let s = img.size
        let f = min(1, maxSide / max(s.width, s.height, 1))
        guard f < 1 else { return img }
        let size = CGSize(width: (s.width * f).rounded(), height: (s.height * f).rounded())
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

struct ReferenceOverlay: View {
    @ObservedObject var ref: ReferenceImage
    @State private var selection: PhotosPickerItem?
    @State private var dragStart: CGPoint?
    @State private var scaleStart: CGFloat?

    var body: some View {
        GeometryReader { g in
            if let img = ref.image {
                let w = max(ref.width * g.size.width, 80)
                let h = w * img.size.height / max(img.size.width, 1)
                let c = CGPoint(x: ref.center.x * g.size.width, y: ref.center.y * g.size.height)
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: w, height: h)
                        .scaleEffect(x: ref.flipped ? -1 : 1, y: 1)
                        .grayscale(ref.gray ? 1 : 0)
                        .opacity(ref.opacity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(ref.locked ? .clear : Brand.mint.opacity(0.8), lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(ref.locked ? 0 : 0.35), radius: 12, y: 4)
                        .allowsHitTesting(!ref.locked)
                        .onTapGesture(count: 2) { ref.locked = true }   // double-tap: lock and trace
                        .gesture(moveAndScale(in: g.size), including: ref.locked ? .none : .all)
                    lockButton.offset(x: 10, y: -10)
                }
                .frame(width: w, height: h)
                .position(c)
                if !ref.locked {
                    controls
                        .position(x: min(max(c.x, 170), g.size.width - 170),
                                  y: min(c.y + h / 2 + 34, g.size.height - 30))
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .animation(Brand.spring, value: ref.locked)
        .photosPicker(isPresented: $ref.pickerShown, selection: $selection, matching: .images)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    ref.set(img)
                }
                selection = nil
            }
        }
    }

    private var lockButton: some View {
        Button { ref.locked.toggle() } label: {
            Image(systemName: ref.locked ? "lock.fill" : "lock.open")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(ref.locked ? 0.6 : 0.95))
                .frame(width: 30, height: 30)
                .tafelOverlayGlass(Circle())
                .accessibilityLabel(ref.locked ? L("Entsperren") : L("Sperren"))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(ref.locked ? 0.55 : 1)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
            Slider(value: $ref.opacity, in: 0.15...1).frame(width: 130).tint(Brand.mint)
            Button { withAnimation(Brand.spring) { ref.flipped.toggle() } } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .foregroundStyle(ref.flipped ? Brand.mint : .primary)
            }
            .accessibilityLabel(L("Ansicht spiegeln"))
            Button { ref.gray.toggle() } label: {
                Image(systemName: "circle.lefthalf.filled.inverse")
                    .foregroundStyle(ref.gray ? Brand.mint : .primary)
            }
            .accessibilityLabel(L("Graustufen-Vorschau"))
            Button { ref.pickerShown = true } label: { Image(systemName: "photo.badge.arrow.down") }
                .accessibilityLabel(L("Anderes Bild"))
            Button(role: .destructive) { withAnimation(Brand.spring) { ref.clear() } } label: { Image(systemName: "trash") }
                .accessibilityLabel(L("Referenzbild entfernen"))
        }
        .font(.system(size: 15, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .tafelOverlayGlass(Capsule())
    }

    private func moveAndScale(in size: CGSize) -> some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { v in
                let start = dragStart ?? ref.center
                dragStart = start
                ref.center = CGPoint(x: min(max(start.x + v.translation.width / size.width, 0.02), 0.98),
                                     y: min(max(start.y + v.translation.height / size.height, 0.02), 0.98))
            }
            .onEnded { _ in dragStart = nil }
        let pinch = MagnifyGesture()
            .onChanged { v in
                let start = scaleStart ?? ref.width
                scaleStart = start
                ref.width = min(max(start * v.magnification, 0.08), 1)
            }
            .onEnded { _ in scaleStart = nil }
        return drag.simultaneously(with: pinch)
    }
}
