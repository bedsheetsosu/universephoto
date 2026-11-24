import SwiftUI
import TafelKit

/// Shown once on the Mac after updating to a version with a changed Mac app.
struct HostWhatsNew: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false
    static let version = "1.0.0"
    static let seenKey = "hostWhatsNewSeen"

    private let items: [(String, String, String)] = [
        ("sidebar.left", L("Neues Fenster"), L("Seitenleiste mit sechs Bereichen; die Übersicht zeigt Verbindung, Aktionen und Quelle. ⌘1–⌘6 wechseln die Bereiche.")),
        ("menubar.rectangle", L("Menüleisten-Panel"), L("Quelle, Fenster aufs iPad, Palette, Zeitraffer, Hitzeschutz und die Profile des iPads mit einem Klick.")),
        ("key.horizontal", L("Kopplungscode"), L("Schwebt über dem Fenster, in drei Vierergruppen wie auf dem iPad.")),
        ("square.on.square.dashed", L("Paletten-Fenster"), L("Ein Mac-Bereich schwebt live auf dem iPad und lässt sich antippen.")),
        ("thermometer.medium", L("Hitzeschutz"), L("Wird der Mac heiß, drosselt sich der Stream – abgedunkelt pausiert er ganz.")),
        ("paintpalette", L("Farbtreue"), L("10-Bit-Farbe und die richtige Tonkurve – Schatten und Verläufe wie am Mac.")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                UltraBadge("sparkles", size: 54)
                    .symbolEffect(.bounce, value: shown)
                    .scaleEffect(shown ? 1 : 0.6)
                Text(L("Neu in %@", Self.version)).font(.system(size: 30, weight: .bold, design: .rounded))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.0)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Brand.slateDeep)
                            .frame(width: 34, height: 34)
                            .background(Ultra.accentFill, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.1).font(.headline)
                            Text(item.2).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ultraCard(padding: 0)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 12)
                    .animation(Ultra.bouncy.delay(0.08 + Double(i) * 0.04), value: shown)
                    .accessibilityElement(children: .combine)
                }
            }
            HStack {
                Spacer()
                Button {
                    UserDefaults.standard.set(Self.version, forKey: Self.seenKey)
                    dismiss()
                } label: {
                    HStack(spacing: 7) {
                        Text(L("Los geht's"))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(UltraProminent(compact: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 640)
        .background(ThemeBackground())
        .preferredColorScheme(.dark)
        .tint(Brand.mint)
        .onAppear { withAnimation(Ultra.bouncy) { shown = true } }
        .onDisappear { UserDefaults.standard.set(Self.version, forKey: Self.seenKey) }
    }
}
