import SwiftUI
import TafelKit

/// Only for the orientation lock: SwiftUI has no API for the allowed orientations.
final class AppDelegate: NSObject, UIApplicationDelegate {
    nonisolated(unsafe) static var allowed: UIInterfaceOrientationMask = .all
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.allowed
    }
}

@main
struct TafelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ClientModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .all)
        }
    }
}

struct RootView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    @ObservedObject private var l10n = L10n.shared
    /// `-debugOpenSettings YES` opens the settings at launch (for screenshots).
    @State private var showSettings = UserDefaults.standard.bool(forKey: "debugOpenSettings")
    /// `-debugOpenCheatSheet YES` / `-debugShowWhatsNew YES`: open those sheets at launch (UI checks).
    @State private var showCheatSheet = UserDefaults.standard.bool(forKey: "debugOpenCheatSheet")
    @State private var showWhatsNew = WhatsNewView.shouldShow || UserDefaults.standard.bool(forKey: "debugShowWhatsNew")
    @State private var showStatus = false

    private var reconnecting: Bool {
        if case .reconnecting = model.phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.demoMode {
                DemoView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(20)
            } else if !model.onboardingDone {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if model.phase.showsCanvas {
                if model.tabletModeActive {
                    TabletSurfaceView()
                        .transition(.opacity)
                }
                CanvasRepresentable(model: model)
                    .grayscale(model.grayscale && !model.tabletModeActive ? 1 : 0)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ReferenceOverlay(ref: model.reference)
                    .transition(.opacity)
                if !model.tabletModeActive {
                    PaletteOverlay(palette: model.palette, send: { model.palettePointer($0) }, close: { model.removePalette() })
                        .zIndex(8)
                }
                overlay
                    .transition(.opacity)
                if model.tabletEditing && model.tabletModeActive {
                    TabletAreaEditor()
                        .transition(.opacity)
                        .zIndex(9)
                }
                if let c = model.radialCenter {
                    RadialMenuView(center: c)
                        .zIndex(10)
                }
                if let img = model.screenshot {
                    ScreenshotView(image: img)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .zIndex(15)
                }
            } else {
                ConnectView(openSettings: { showSettings = true })
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.phase.showsCanvas)
        .animation(.easeInOut(duration: 0.3), value: model.settings.tabletMode)
        .animation(Brand.spring, value: model.radialCenter != nil)
        .sensoryFeedback(.pathComplete, trigger: model.radialCenter == nil) { old, new in !old && new }
        .animation(.easeInOut(duration: 0.45), value: model.onboardingDone)
        .animation(Brand.spring, value: model.demoMode)
        .animation(Brand.spring, value: model.screenshot != nil)
        .id(l10n.language)   // re-render every text when the language changes
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(model)
                .presentationSizing(.page)
                .presentationBackground { ThemeBackground() }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: WhatsNewView.markSeen) {
            WhatsNewView()
                .presentationSizing(.page)
                .presentationBackground { ThemeBackground() }
        }
        .sheet(isPresented: $showCheatSheet) {
            CheatSheetView().environmentObject(model)
                .presentationSizing(.page)
                .presentationBackground { ThemeBackground() }
        }
    }

    private func undoButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        UltraRoundButton(symbol, label: label, size: 50, action: action)
    }

    private var overlay: some View {
        ZStack {
            if model.settings.undoButtons && !model.tabletModeActive && !model.settings.viewOnly {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        if !model.settings.shortcutBarOnRight { Spacer() }
                        undoButton("arrow.uturn.backward", L("Widerrufen")) { model.trigger(.undo) }
                        undoButton("arrow.uturn.forward", L("Wiederholen")) { model.trigger(.redo) }
                        if model.settings.shortcutBarOnRight { Spacer() }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 18)
                }
            }
            if model.settings.showShortcutBar && !model.tabletModeActive && !model.settings.viewOnly {
                HStack {
                    if model.settings.shortcutBarOnRight { Spacer() }
                    ShortcutBar()
                    if !model.settings.shortcutBarOnRight { Spacer() }
                }
                .padding(.horizontal, 8)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    Spacer()
                    if showStatus || model.showStatusOverlay {
                        StatusPill()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    UltraRoundButton(model.commandOpen ? "xmark" : "square.grid.2x2.fill",
                                     label: model.commandOpen ? L("Menü schließen") : L("Menü"), size: 40) {
                        withAnimation(Ultra.smooth) { model.commandOpen.toggle() }
                    }
                }
                if let t = model.toast {
                    Text(t.text)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .ultraPanel(Capsule())
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
                        .id(t.text)
                }
                if (model.localZoom > 1.01 || model.localAngle != 0) && model.settings.zoomMethod == .localView {
                    Button {
                        model.localZoomResets += 1
                    } label: {
                        Label((model.localAngle != 0 ? "\(model.localAngle)° · " : "") + L("%d %% · Zurücksetzen", Int((model.localZoom * 100).rounded())),
                              systemImage: model.localAngle != 0 ? "rotate.right" : "arrow.up.left.and.down.right.magnifyingglass")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .ultraPanel(Capsule(), shadow: false)
                    }
                    .buttonStyle(UltraPress())
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let n = model.scrubSteps {
                    ScrubPill(steps: n)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if reconnecting {
                    ReconnectBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(10)
            if model.commandOpen {
                // No backdrop: the next touch on the canvas closes it (see CanvasView.chromeOpen).
                GeometryReader { g in
                    VStack {
                        HStack {
                            Spacer()
                            CommandCenter(
                                close: { withAnimation(Ultra.smooth) { model.commandOpen = false } },
                                toggleStatus: { withAnimation(Ultra.smooth) { showStatus.toggle() } }, showStatus: showStatus,
                                openSettings: { showSettings = true },
                                openCheatSheet: { showCheatSheet = true },
                                maxHeight: max(g.size.height - 16, 200))
                        }
                        Spacer()
                    }
                }
                .padding(.top, 58).padding(.trailing, 10)
                .transition(.scale(scale: 0.86, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(Brand.spring, value: reconnecting)
        .animation(Ultra.smooth, value: model.commandOpen)
        .animation(Brand.spring, value: model.scrubSteps != nil)
        .animation(Brand.spring, value: model.toast)
        .animation(Brand.spring, value: showStatus || model.showStatusOverlay)
    }
}

/// Undo scrub feedback: "↶ 3" while dragging left, "↷ 2" right.
private struct ScrubPill: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let steps: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: steps < 0 ? "arrow.uturn.backward" : steps > 0 ? "arrow.uturn.forward" : "arrow.left.and.right")
            Text(steps == 0 ? L("Ziehen: links Undo, rechts Redo") : "\(abs(steps))")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 18).padding(.vertical, 11)
        .ultraPanel(Capsule(), shadow: false)
        .animation(Brand.spring, value: steps)
        .allowsHitTesting(false)
    }
}

private struct ReconnectBanner: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Brand.mint)
            Text(L("Verbindung unterbrochen – verbinde neu …"))
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .ultraPanel(Capsule(), shadow: false)
        .allowsHitTesting(false)
    }
}

struct StatusPill: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel

    var body: some View {
        HStack(spacing: 10) {
            if let t = model.timing {
                let usb = t.link.hasPrefix("USB")
                Image(systemName: usb ? "cable.connector" : "wifi")
                    .foregroundStyle(usb ? Brand.mint : .orange)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(usb ? L("USB-Kabel") : L("WLAN"))
                metric(t.rttMs, "ms RTT")
                if let age = t.frameAgeMs { metric(age, L("ms Bild")) }
                metric(t.fps, "fps")
            } else {
                ProgressView().controlSize(.mini)
                Text(L("misst …"))
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 14)
        .frame(height: 40)
        .ultraPanel(Capsule(), shadow: false)
    }

    private func metric(_ v: Double, _ unit: String) -> some View {
        HStack(spacing: 3) {
            Text("\(Int(v.rounded()))")
                .fontWeight(.semibold)
                .contentTransition(.numericText(value: v))
                .animation(.snappy, value: Int(v.rounded()))
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct ShortcutBar: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.currentBar) { b in
                if let key = b.hold {
                    HoldButton(title: b.title, key: key)
                } else {
                    Button {
                        model.run(b)
                    } label: {
                        barLabel(b.title, active: false)
                    }
                    .buttonStyle(PressScale())
                }
            }
        }
        .animation(Brand.spring, value: model.currentBar.map(\.id))
    }
}

func barLabel(_ title: String, active: Bool) -> some View {
    Text(title)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .frame(width: 64, height: 40)
        .foregroundStyle(active ? Brand.slateDeep : Color.white.opacity(0.92))
        .background(active ? AnyShapeStyle(Ultra.accentFill) : AnyShapeStyle(Color.clear), in: Ultra.shape(12))
        .ultraPanel(Ultra.shape(12), shadow: false)
}

/// Holds a key (⇧, ⌥, ⌘, ⌃, Space) down while the finger rests on it – works while the Pencil
/// draws with the other hand.
struct HoldButton: View {
    @EnvironmentObject var model: ClientModel
    let title: String
    let key: HoldKey
    @State private var down = false

    var body: some View {
        barLabel(title, active: down)
            .scaleEffect(down ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: down)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; model.hold(key, down: true) } }
                .onEnded { _ in down = false; model.hold(key, down: false) })
            .onDisappear { if down { down = false; model.hold(key, down: false) } }
    }
}

/// Springy press feedback.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
