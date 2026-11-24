import AppKit
import SwiftUI

/// Animate as its own module (0.106). Photo and Animate keep their own documents (tabs); both
/// stay open when you switch – nothing asks to save until the whole app quits. "Push" hands the
/// picture to the other module: Photo → Animate as the next frame or a new animation, Animate →
/// Photo as a new layer or a new picture. The module you leave shrinks into a bubble top left.
extension Studio {
    var currentTabIsAnimation: Bool { tabs.first { $0.id == tabID }?.animate ?? false }
    /// The open documents that belong to Photo (false) or Animate (true).
    func tabs(animate: Bool) -> [OpenArtwork] { tabs.filter { $0.animate == animate } }
    /// The document the other module would come back to.
    func returnTab(animate: Bool) -> OpenArtwork? {
        lastTab[animate].flatMap { id in tabs.first { $0.id == id && $0.animate == animate } } ?? tabs(animate: animate).last
    }

    /// Makes sure the document on screen belongs to the module: the last one used there, or a
    /// fresh one when there is none yet.
    func showDocument(animate: Bool) {
        guard currentTabIsAnimation != animate else { return }
        syncTab(); lastTab[!animate] = tabID
        if let t = returnTab(animate: animate) { switchTab(t.id) } else { newDocument(background: Self.preferredBackground, animate: animate) }
    }

    /// Takes the current picture to the other module. `asNew`: a new document there (layers and
    /// all); otherwise into the document open there – the next frame in Animate, a new layer in
    /// Photo. Returns true when something was handed over.
    @discardableResult func push(asNew: Bool) -> Bool {
        let toAnimate = !currentTabIsAnimation
        stopPlayback(); syncTab()
        let picture = layers, w = width, h = height, title = documentName
        let target = asNew ? nil : returnTab(animate: toAnimate)
        lastTab[!toAnimate] = tabID
        if let target {
            switchTab(target.id)
            guard let image = Renderer.render(layers: composite(picture), width: w, height: h) else { return false }
            if toAnimate { importFrames([(image, nil)]) }
            else if let png = ImageFiles.fitted(image, width: width, height: height).flatMap({ try? Renderer.png($0) }) {
                checkpoint("Push to Photo")
                var l = ArtLayer(name: title); l.imageData = png
                layers.append(l); selectedLayer = layers.count - 1; changed()
            }
        } else {
            tabID = UUID(); fileURL = nil; frameIndex = 0
            apply(ArtDocument(title: title, width: w, height: h, layers: picture))
            selectedLayer = max(0, layers.count - 1)
            savedDocument = nil; dirty = true; undoStack = []; redoStack = []
            tabs.append(OpenArtwork(id: tabID, document: document(), url: nil, dirty: true, animate: toAnimate)); fit()
            changed()
        }
        module = toAnimate ? .animate : .photo
        return true
    }

    /// Titles of the documents with unsaved changes, Photo and Animate apart, for the quit alert.
    func unsavedSummary() -> String {
        syncTab()
        func list(_ a: Bool) -> [String] { tabs(animate: a).filter(\.dirty).map(\.document.title) }
        var parts: [String] = []
        if !list(false).isEmpty { parts.append(L("Photo") + ": " + list(false).joined(separator: ", ")) }
        if !list(true).isEmpty { parts.append(L("Animate") + ": " + list(true).joined(separator: ", ")) }
        return parts.joined(separator: "\n")
    }
}

/// The other module, shrunk into a bubble top left: a small picture of its document; a click
/// brings it back.
struct ModuleBubble: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    let animate: Bool
    @State private var thumb: CGImage?
    var body: some View {
        let tab = s.returnTab(animate: animate)
        Button { withAnimation(PhotoMotion.panel) { s.enter(animate ? .animate : .photo) } } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(theme.card)
                    if let thumb { Image(decorative: thumb, scale: 1).resizable().scaledToFit().padding(4).clipShape(Circle()) }
                    else { Image(systemName: animate ? "play.rectangle" : "camera.aperture").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent) }
                }.frame(width: 26, height: 26).overlay(Circle().strokeBorder(theme.accent.opacity(0.7), lineWidth: 1.2))
                Text(L(animate ? "Animate" : "Photo")).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
            }.padding(.leading, 3).padding(.trailing, 10).frame(height: 32)
            .background(theme.deep.opacity(0.55), in: Capsule()).overlay(Capsule().strokeBorder(theme.outline, lineWidth: 0.75))
        }.buttonStyle(PhotoPress()).help(L(animate ? "Back to Animate – the animation stays open" : "Back to Photo – the picture stays open"))
        .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
        .task(id: tab?.id) { thumb = tab.flatMap { Self.thumbnail($0.document) } }
    }

    static func thumbnail(_ d: ArtDocument) -> CGImage? {
        let k = 64 / Double(max(d.width, d.height))
        guard let full = Renderer.render(layers: d.layers, width: d.width, height: d.height) else { return nil }
        return ImageFiles.fitted(full, width: max(1, Int(Double(d.width) * k)), height: max(1, Int(Double(d.height) * k)))
    }
}

/// The push button with its question: into the open document over there, or a new one.
struct PushButton: View {
    @EnvironmentObject var s: Studio
    let toAnimate: Bool
    @State private var asking = false
    var body: some View {
        Button {
            if s.returnTab(animate: toAnimate) == nil { go(asNew: true) } else { asking = true }
        } label: { Label(L(toAnimate ? "Push to Animate" : "Push to Photo"), systemImage: toAnimate ? "arrow.right.circle" : "arrow.left.circle") }
        .buttonStyle(PhotoButtonStyle())
        .help(L(toAnimate ? "Takes this picture to Animate – Photo keeps it open" : "Takes this frame to Photo – the animation stays open"))
        .confirmationDialog(L(toAnimate ? "Push to Animate" : "Push to Photo"), isPresented: $asking) {
            Button(L(toAnimate ? "As the next frame" : "As a new layer")) { go(asNew: false) }
            Button(L(toAnimate ? "As a new animation" : "As a new picture")) { go(asNew: true) }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(LF(toAnimate ? "Into “%@” or as its own project?" : "Into “%@” or as its own picture?", s.returnTab(animate: toAnimate)?.document.title ?? ""))
        }
    }
    func go(asNew: Bool) { withAnimation(PhotoMotion.panel) { _ = s.push(asNew: asNew) } }
}

enum ModuleSwap {
    @MainActor static var transition: AnyTransition { .asymmetric(
        insertion: .scale(scale: 1.03).combined(with: .opacity),
        removal: .scale(scale: 0.04, anchor: UnitPoint(x: 0.1, y: 0.04)).combined(with: .opacity)) }
}
