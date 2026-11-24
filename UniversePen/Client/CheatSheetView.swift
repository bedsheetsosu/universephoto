import SwiftUI
import TafelKit

/// Everything the Pencil, the fingers and the Mac shortcuts do right now, on one page.
struct CheatSheetView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false

    var body: some View {
        let s = model.effectiveSettings
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        UltraBadge("hand.draw", size: 58)
                            .scaleEffect(shown ? 1 : 0.6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Gesten & Kürzel")).font(.system(size: 34, weight: .bold, design: .rounded))
                            Text(L("Was Stift, Finger und Mac gerade tun.")).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                        card(L("Pencil"), symbol: "applepencil", index: 0) {
                            entry("applepencil.doubletap", L("Doppeltippen"), s.doubleTap.display)
                            entry("applepencil.squeeze", L("Squeeze"), s.squeeze.display)
                            if let k = s.squeezeHoldKey { entry("applepencil.squeeze", L("Squeeze halten"), k == .space ? L("Leertaste") : k.symbol) }
                            if s.shapeRecognition { entry("scribble.variable", L("Formerkennung"), L("Am Strichende kurz halten")) }
                            if s.ropeLength > 0 { entry("lasso", L("Seil-Stabilisator: %d pt", Int(s.ropeLength)), "") }
                        }
                        card(L("Finger"), symbol: "hand.raised", index: 1) {
                            entry("hand.tap", L("Zwei-Finger-Tipp"), s.twoFingerTap.display)
                            entry("hand.tap", L("Drei-Finger-Tipp"), s.threeFingerTap.display)
                            entry("hand.tap", L("Vier-Finger-Tipp"), s.fourFingerTap.display)
                            entry("arrow.left", L("Drei Finger nach links"), s.threeFingerSwipeLeft.display)
                            entry("arrow.right", L("Drei Finger nach rechts"), s.threeFingerSwipeRight.display)
                            entry("arrow.up", L("Drei Finger nach oben"), s.threeFingerSwipeUp.display)
                            entry("arrow.down", L("Drei Finger nach unten"), s.threeFingerSwipeDown.display)
                            entry("arrow.up.left.and.arrow.down.right", L("Zoomen (Pinch)"), s.zoomMethod.title)
                            entry("rotate.right", L("Drehen links"), s.rotateLeft.display)
                            entry("rotate.left", L("Drehen rechts"), s.rotateRight.display)
                            if s.undoScrub { entry("arrow.uturn.backward", L("Undo-Wischen (zwei Finger halten, dann ziehen)"), "") }
                        }
                        card(L("Mac"), symbol: "keyboard", index: 2) {
                            shortcut("⌃⌥⌘T", L("Tablett-Modus"), symbol: "rectangle.dashed")
                            shortcut("⌃⌥⌘P", L("Palette fürs iPad wählen …"), symbol: "square.on.square.dashed")
                            shortcut("⌃⌥⌘I", L("Vorderstes Fenster aufs iPad"), symbol: "macwindow.badge.plus")
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.vertical, 28)
            }
            .scrollIndicators(.hidden)
            UltraRoundButton("xmark", label: L("Fertig"), size: 44) { dismiss() }
                .padding(20)
        }
        .preferredColorScheme(.dark)
        .onAppear { withAnimation(Ultra.bouncy) { shown = true } }
    }

    private func card<Content: View>(_ title: String, symbol: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(Brand.mintBright)
            VStack(spacing: 0) {
                Group(subviews: content()) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.leading, 42) }
                        row
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ultraGlass(Ultra.shape(Ultra.cardRadius))
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 18)
        .animation(Ultra.bouncy.delay(0.06 + Double(index) * 0.07), value: shown)
    }

    private func entry(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.09), in: Ultra.shape(9))
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.medium))
            Spacer(minLength: 8)
            if !value.isEmpty {
                Text(value)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.1), in: Capsule())
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func shortcut(_ keys: String, _ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.09), in: Ultra.shape(9))
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.medium))
            Spacer(minLength: 8)
            UltraKeyCaps(keys)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
