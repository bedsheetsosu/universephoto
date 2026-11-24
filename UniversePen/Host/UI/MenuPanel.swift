import SwiftUI
import TafelKit

/// The menu bar panel: connection at a glance, source and quick actions as tiles, then the
/// usual entries. It stays alive while hidden, so nothing in it animates on its own.
struct HostMenuPanel: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var host: HostController
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openWindow) private var openWindow

    private var connected: Bool { host.sessionDevice != nil }
    private let two = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    private let four = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            UltraHeader(L("Quelle"))
            LazyVGrid(columns: two, spacing: 8) {
                ForEach(CaptureMode.allCases) { m in
                    UltraTile(m.title, symbol: m.symbol, on: host.mode == m,
                              enabled: m != .virtual || HostController.secondScreenAvailable, minHeight: 54) {
                        host.mode = m
                    }
                }
            }
            UltraHeader(L("Aktionen"))
            LazyVGrid(columns: four, spacing: 8) {
                UltraTile(L("Fenster"), symbol: "macwindow.badge.plus", enabled: connected && host.mode != .window, minHeight: 58) {
                    host.moveFrontWindowToIPad()
                }
                .help(L("Vorderstes Fenster aufs iPad"))
                UltraTile(L("Palette"), symbol: "square.on.square.dashed", on: host.paletteArea != nil, minHeight: 58) {
                    if host.paletteArea == nil { host.pickPalette() } else { host.removePalette() }
                }
                .help(host.paletteArea == nil ? L("Palette fürs iPad wählen …") : L("Palette entfernen"))
                UltraTile(L("Zeitraffer"), symbol: host.timelapseRunning ? "stop.circle.fill" : "record.circle",
                          on: host.timelapseRunning, enabled: connected || host.timelapseRunning, minHeight: 58) {
                    host.timelapseRunning ? host.stopTimelapse() : host.startTimelapse()
                }
                UltraTile(L("Hitzeschutz"), symbol: "thermometer.medium", on: host.heatGuard, minHeight: 58) {
                    host.heatGuard.toggle()
                }
            }
            if host.heatLevel > 0 {
                Label(host.heatGuard ? L("Mac ist heiß – Stream gedrosselt (30 fps).") : L("Mac ist heiß."), systemImage: "thermometer.high")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 4)
            }
            if connected && !host.ipadProfiles.isEmpty {
                UltraHeader(L("Profil"))
                VStack(spacing: 0) {
                    ForEach(host.ipadProfiles, id: \.id) { p in
                        UltraRow(p.name, symbol: "person.crop.square", checked: p.id == host.ipadActiveProfile) {
                            host.activateIPadProfile(p.id)
                        }
                    }
                }
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            VStack(spacing: 0) {
                UltraRow(L("iPad koppeln …"), symbol: "ipad.and.arrow.forward") {
                    openMain()
                    host.beginPairing()
                }
                UltraRow(L("Plugins …"), symbol: "puzzlepiece.extension") {
                    openWindow(id: "plugins")
                    NSApp.activate()
                }
                UltraRow(L("UniversePen öffnen"), symbol: "macwindow") { openMain() }
                UltraRow(L("UniversePen beenden"), symbol: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
        .tint(Brand.mint)
        .environment(\.colorScheme, .dark)
        .id(l10n.language)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ConnectionOrb(connected: connected, usb: host.sessionLink.hasPrefix("USB"), animated: false)
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.sessionDevice ?? (host.listenerReady ? L("Warte auf das iPad …") : host.listenerStatus))
                    .font(.headline).lineLimit(1)
                if connected {
                    StatsLine(live: host.live, link: host.sessionLink)
                } else {
                    Text(L("UniversePen auf dem iPad öffnen – es verbindet sich automatisch."))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let b = host.ipadBattery, connected {
                BatteryChip(level: b, charging: host.ipadCharging == true)
            }
        }
        .padding(.bottom, 2)
    }

    private func openMain() { showMainWindow(openWindow) }
}
