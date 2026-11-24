import SwiftUI
import TafelKit

// MARK: - Start screen

/// Where the app opens: the mark and what it is on one side, your Macs as glass cards on the
/// other (stacked in portrait). Nothing streams here, so this screen may move and use real
/// Liquid Glass.
struct ConnectView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    var openSettings: () -> Void = {}
    @State private var pairTarget: DiscoveredHost?
    @State private var appeared = false

    private var searching: Bool {
        if case .idle = model.phase { return model.discovered.filter { model.isPaired($0) }.isEmpty }
        return false
    }

    private var connectingName: String? {
        if case .connecting(let n) = model.phase { return n }
        return nil
    }

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > 900
            ZStack(alignment: .topTrailing) {
                ThemeBackground().ignoresSafeArea()
                if wide {
                    HStack(spacing: 0) {
                        hero
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        ScrollView {
                            column
                                .padding(.vertical, 56).padding(.trailing, 44).padding(.leading, 8)
                                .frame(minHeight: g.size.height, alignment: .center)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(width: min(g.size.width * 0.47, 580))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 30) {
                            hero
                            column.frame(maxWidth: 620)
                        }
                        .padding(.horizontal, 24).padding(.vertical, 56)
                        .frame(maxWidth: .infinity)
                    }
                }
                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .ultraGlass(Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(UltraPress(scale: 0.9))
                .accessibilityLabel(L("Einstellungen …"))
                .padding(18)
                .opacity(appeared ? 1 : 0)
            }
        }
        .animation(Ultra.smooth, value: model.discovered.map(\.id))
        .animation(Ultra.smooth, value: model.pairable.map(\.id))
        .animation(Ultra.smooth, value: model.phase)
        .sheet(item: $pairTarget) { host in
            PairingSheet(host: host).environmentObject(model)
        }
        .onAppear { withAnimation(Ultra.bouncy.delay(0.05)) { appeared = true } }
        .task {
            // `-debugPairingSheet YES` (with -debugNoAutoConnect) opens the code entry for the first
            // Mac found, for UI checks. Nothing is sent until a code is typed and confirmed.
            guard UserDefaults.standard.bool(forKey: "debugPairingSheet") else { return }
            for _ in 0..<20 where pairTarget == nil {
                if let h = model.discovered.first { pairTarget = h; break }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 20) {
            ZStack {
                PulseRings(color: Brand.mint, active: searching)
                    .frame(width: 200, height: 200)
                TafelMark()
                    .frame(width: 132, height: 132)
                    .shadow(color: Brand.mint.opacity(0.45), radius: 36)
            }
            .frame(height: 170)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            VStack(spacing: 8) {
                Text("UniversePen")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                Text(L("Dein iPad als Zeichendisplay für den Mac"))
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .offset(y: appeared ? 0 : 18)
            .opacity(appeared ? 1 : 0)
            statusLine
                .frame(minHeight: 44)
        }
        .padding(32)
    }

    @ViewBuilder private var statusLine: some View {
        if let name = connectingName {
            chip { ProgressView().tint(Brand.mint) } text: { L("Verbinde mit %@ …", name) }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if searching && !model.paired.isEmpty {
            chip {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.mint)
                    .symbolEffect(.pulse, options: .repeating)
            } text: { L("Suche deinen Mac … UniversePen Host muss laufen.") }
                .transition(.opacity)
        }
    }

    private func chip(@ViewBuilder icon: () -> some View, text: () -> String) -> some View {
        HStack(spacing: 10) {
            icon()
            Text(text()).font(.callout.weight(.medium)).multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .ultraGlass(Capsule())
    }

    // MARK: Column

    private var column: some View {
        VStack(alignment: .leading, spacing: 24) {
            if case .failed(let msg) = model.phase {
                VStack(alignment: .leading, spacing: 14) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                    Button {
                        model.retry()
                    } label: {
                        Label(L("Erneut versuchen"), systemImage: "arrow.clockwise")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Brand.slateDeep)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Ultra.accentFill, in: Capsule())
                    }
                    .buttonStyle(UltraPress())
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ultraGlass(Ultra.shape(26), tint: .orange.opacity(0.25))
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            if !model.paired.isEmpty {
                section(L("Deine Macs")) {
                    ForEach(model.paired) { p in
                        let host = model.discovered.first { $0.hostID == p.id }
                        HostCard(name: p.name, host: host, connecting: connectingName == p.name) {
                            if let host { model.connect(host) }
                        }
                        .contextMenu {
                            Button(role: .destructive) { model.forget(p) } label: { Label(L("Kopplung entfernen"), systemImage: "trash") }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            section(L("Neu koppeln")) {
                if model.pairable.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "laptopcomputer.and.arrow.down")
                            .font(.title2).foregroundStyle(.secondary)
                            .frame(width: 44)
                        Text(L("Am Mac in UniversePen Host „iPad koppeln …“ wählen – der Mac erscheint dann hier."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ultraGlass(Ultra.shape(26))
                }
                ForEach(model.pairable) { h in
                    Button {
                        pairTarget = h
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "link.badge.plus")
                                .font(.title2.weight(.medium)).foregroundStyle(Brand.slateDeep)
                                .symbolEffect(.pulse, options: .repeating)
                                .frame(width: 56, height: 56)
                                .background(Ultra.accentFill, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(h.name).font(.title3.weight(.semibold))
                                Text(L("bereit zum Koppeln")).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .ultraGlass(Ultra.shape(26), interactive: true)
                        .contentShape(Ultra.shape(26))
                    }
                    .buttonStyle(UltraPress(scale: 0.97))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(Brand.spring) { model.demoMode = true }
                } label: {
                    Label(L("Ohne Mac ausprobieren (Demo)"), systemImage: "sparkles")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .ultraGlass(Capsule(), interactive: true)
                        .contentShape(Capsule())
                }
                .buttonStyle(UltraPress())
                Text(L("Nur Geräte mit dem einmaligen Code vom Mac werden gekoppelt. Verbindungen laufen verschlüsselt und direkt – per Kabel oder im lokalen Netz, ohne Server, Konto oder Cloud."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .offset(y: appeared ? 0 : 24)
        .opacity(appeared ? 1 : 0)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Brand.mintBright)
                .padding(.leading, 6)
            UltraGlassGroup(spacing: 12) {
                VStack(spacing: 12) { content() }
            }
        }
    }
}

private struct HostCard: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let name: String
    let host: DiscoveredHost?
    let connecting: Bool
    let connect: () -> Void

    var body: some View {
        let reachable = host != nil
        let cable = !(host?.cableInterfaces.isEmpty ?? true)
        Button(action: connect) {
            HStack(spacing: 16) {
                Image(systemName: "laptopcomputer")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(reachable ? Brand.slateDeep : Color.secondary)
                    .frame(width: 56, height: 56)
                    .background {
                        if reachable { Circle().fill(Ultra.accentFill) } else { Circle().fill(.white.opacity(0.08)) }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.title3.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: reachable ? (cable ? "cable.connector" : "wifi") : "wifi.slash")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(reachable ? Brand.mint : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                        Text(reachable ? (cable ? L("erreichbar · per Kabel") : L("erreichbar · WLAN")) : L("nicht gefunden"))
                            .font(.callout).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                }
                Spacer(minLength: 8)
                if connecting {
                    ProgressView().tint(Brand.mint).padding(.trailing, 8)
                        .transition(.scale.combined(with: .opacity))
                } else if reachable {
                    Text(L("Verbinden"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Brand.slateDeep)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Ultra.accentFill, in: Capsule())
                        .shadow(color: Brand.mint.opacity(0.4), radius: 10, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
            .ultraGlass(Ultra.shape(26), interactive: reachable)
            .contentShape(Ultra.shape(26))
        }
        .buttonStyle(UltraPress(scale: 0.97))
        .disabled(!reachable || connecting)
        .animation(Ultra.smooth, value: reachable)
        .animation(Ultra.smooth, value: connecting)
    }
}

// MARK: - Pairing sheet

private struct PairingSheet: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    @Environment(\.dismiss) private var dismiss
    let host: DiscoveredHost
    @State private var code = ""
    @FocusState private var focused: Bool
    @State private var shake = 0

    private var normalized: String? { PairingCode.normalize(code) }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.laptopcomputer")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(Brand.mint)
                .symbolEffect(.bounce, value: model.pairingBusy)
            VStack(spacing: 6) {
                Text(L("Mit %@ koppeln", host.name)).font(.title2.weight(.bold))
                Text(L("Gib den 12-stelligen Code ein, den UniversePen Host auf dem Mac zeigt."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            // The boxes show what is typed; the (nearly invisible) field on top takes the keys,
            // so paste, hardware keyboards and dictation all work.
            CodeBoxes(text: code, valid: normalized != nil, focused: focused)
                .overlay {
                    TextField("", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused)
                        .onSubmit(submit)
                        .opacity(0.011)
                        .accessibilityLabel("XXXX-XXXX-XXXX")
                }
                .modifier(Shake(animatableData: CGFloat(shake)))
            if let e = model.pairingError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .transition(.opacity)
            }
            HStack(spacing: 12) {
                Button(L("Abbrechen")) { dismiss() }
                    .buttonStyle(UltraQuiet())
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if model.pairingBusy { ProgressView().tint(Brand.slateDeep) }
                        Text(L("Koppeln"))
                    }
                    .frame(minWidth: 110)
                }
                .buttonStyle(UltraProminent())
                .disabled(normalized == nil || model.pairingBusy)
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: 520)
        .presentationDetents([.medium])
        .presentationBackground { ThemeBackground() }
        .animation(Brand.spring, value: model.pairingError)
        .animation(Ultra.snappy, value: code)
        .onAppear {
            model.pairingError = nil
            focused = true
        }
        .onChange(of: model.pairingBusy) { _, busy in
            guard !busy else { return }
            if model.pairingError == nil {
                dismiss()
            } else {
                withAnimation(.default) { shake += 1 }
            }
        }
    }

    private func submit() {
        guard normalized != nil, !model.pairingBusy else { return }
        model.pair(with: host, code: code)
    }
}

/// Twelve boxes in three groups for the pairing code.
private struct CodeBoxes: View {
    @ObservedObject private var theme = Theme.shared
    let text: String
    let valid: Bool
    let focused: Bool

    private var chars: [Character] {
        Array(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(12))
    }

    var body: some View {
        let c = chars
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { g in
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { i in
                        let idx = g * 4 + i
                        let filled = idx < c.count
                        Text(filled ? String(c[idx]) : " ")
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .frame(width: 32, height: 46)
                            .background(.white.opacity(filled ? 0.12 : 0.05), in: Ultra.shape(10))
                            .overlay(Ultra.shape(10).strokeBorder(
                                valid ? Brand.mint : (focused && idx == c.count ? Brand.mint.opacity(0.9) : .white.opacity(0.12)),
                                lineWidth: 1.5))
                            .scaleEffect(filled ? 1 : 0.96)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Horizontal shake for a wrong code.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}
