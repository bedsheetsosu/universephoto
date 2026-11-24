import SwiftUI
import UIKit
import TafelKit

/// Screenshot from the Mac (full resolution of what is streamed). Drag with a finger or the
/// Pencil to crop, then share it or save it to Photos.
struct ScreenshotView: View {
    @EnvironmentObject var model: ClientModel
    let image: UIImage
    @State private var start: CGPoint?
    @State private var selection: CGRect?
    @State private var shareItem: ShareImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 16) {
                GeometryReader { g in
                    let d = Geometry.aspectFit(content: image.size, in: CGRect(origin: .zero, size: g.size))
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: d.width, height: d.height)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: .black.opacity(0.5), radius: 20)
                            .offset(x: d.minX, y: d.minY)
                        if let sel = selection {
                            // Dim everything outside the crop.
                            Path { p in
                                p.addRect(d)
                                p.addRect(sel)
                            }
                            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                            Rectangle()
                                .strokeBorder(Brand.mintBright, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                                .shadow(color: Brand.mint.opacity(0.6), radius: 6)
                                .frame(width: sel.width, height: sel.height)
                                .offset(x: sel.minX, y: sel.minY)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { v in
                                let a = start ?? v.startLocation
                                start = a
                                let r = CGRect(x: min(a.x, v.location.x), y: min(a.y, v.location.y),
                                               width: abs(v.location.x - a.x), height: abs(v.location.y - a.y))
                                selection = r.intersection(d)
                            }
                            .onEnded { _ in
                                start = nil
                                if let s = selection, s.width < 12 || s.height < 12 { selection = nil }
                            }
                    )
                    .onAppear { displayRect = d }
                    .onChange(of: g.size) { _, _ in displayRect = Geometry.aspectFit(content: image.size, in: CGRect(origin: .zero, size: g.size)) }
                }
                Text(selection == nil ? L("Zum Zuschneiden einen Bereich aufziehen") : L("%d × %d Pixel", Int(cropRect.width), Int(cropRect.height)))
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .ultraPanel(Capsule(), shadow: false)
                    .contentTransition(.numericText())
                HStack(spacing: 8) {
                    Button(L("Abbrechen")) { withAnimation(Ultra.smooth) { model.screenshot = nil } }
                        .buttonStyle(UltraQuiet(compact: true))
                    if selection != nil {
                        Button(L("Ganzes Bild")) { withAnimation(Ultra.snappy) { selection = nil } }
                            .buttonStyle(UltraQuiet(compact: true))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Button {
                        UIImageWriteToSavedPhotosAlbum(output(), nil, nil, nil)
                        model.show(Toast(text: L("In Fotos gesichert"), seconds: 1.6))
                        withAnimation(Ultra.smooth) { model.screenshot = nil }
                    } label: { Label(L("In Fotos sichern"), systemImage: "photo.on.rectangle.angled") }
                        .buttonStyle(UltraQuiet(compact: true))
                    Button {
                        model.copyToMac(output())
                        withAnimation(Ultra.smooth) { model.screenshot = nil }
                    } label: { Label(L("Auf den Mac kopieren"), systemImage: "doc.on.clipboard") }
                        .buttonStyle(UltraQuiet(compact: true))
                    Button {
                        shareItem = ShareImage(image: output())
                    } label: { Label(L("Teilen …"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(UltraProminent(compact: true))
                }
                .padding(7)
                .ultraPanel(Capsule())
                .animation(Ultra.snappy, value: selection == nil)
            }
            .padding(28)
        }
        .sheet(item: $shareItem) { item in
            ActivitySheet(items: [item.image]).presentationDetents([.medium, .large])
        }
    }

    @State private var displayRect: CGRect = .zero

    /// Selection in image pixels.
    private var cropRect: CGRect {
        guard let cg = image.cgImage else { return .zero }
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        guard let sel = selection, displayRect.width > 0 else { return full }
        let sx = CGFloat(cg.width) / displayRect.width, sy = CGFloat(cg.height) / displayRect.height
        return CGRect(x: (sel.minX - displayRect.minX) * sx, y: (sel.minY - displayRect.minY) * sy,
                      width: sel.width * sx, height: sel.height * sy).integral.intersection(full)
    }

    private func output() -> UIImage {
        guard selection != nil, let cg = image.cgImage?.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}

private struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
