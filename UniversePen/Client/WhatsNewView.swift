import SwiftUI
import TafelKit

/// Shown once after updating to a version with new features.
struct WhatsNewView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false
    static let version = "1.0.0"
    static let seenKey = "whatsNewSeen"

    static var shouldShow: Bool {
        // Not on a fresh install (onboarding explains everything), only after an update.
        guard UserDefaults.standard.object(forKey: "pairedHosts") != nil else {
            UserDefaults.standard.set(version, forKey: seenKey)
            return false
        }
        return UserDefaults.standard.string(forKey: seenKey) != version
    }

    static func markSeen() { UserDefaults.standard.set(version, forKey: seenKey) }

    private let items: [(String, String, String)] = [
        ("square.grid.2x2", L("Neues Design"), L("Kontrollzentrum mit vier Bereichen, Einstellungen mit Suche, Liquid Glass – auf iPad und Mac.")),
        ("paintpalette", L("Farbtreue"), L("10-Bit-Farbe und die richtige Tonkurve – Schatten und Verläufe wie am Mac.")),
        ("perspective", L("Zeichenhilfen"), L("Perspektive mit 1–3 Fluchtpunkten, Ellipsen-Schablone, Raster – jede App merkt sich ihre.")),
        ("scribble.variable", L("Formerkennung"), L("Am Strichende kurz halten: Linie, Pfeil, Kreis, Rechteck werden sauber.")),
        ("lasso", L("Ruhige Linien"), L("Seil-Stabilisator, Tempo-Druck, fester Druck und Druckkurven-Vorlagen.")),
        ("rotate.right", L("Ansicht"), L("Drehen wie ein Blatt Papier, spiegeln, Graustufen – nur auf dem iPad.")),
        ("square.on.square.dashed", L("Paletten-Fenster"), L("Ein Mac-Bereich schwebt live auf dem iPad und lässt sich antippen.")),
        ("applepencil.squeeze", L("Squeeze halten"), L("Hält eine Taste, solange du drückst – z. B. Leertaste zum Verschieben.")),
        ("rectangle.dashed", L("Tablett-Modus automatisch"), L("Schaltet sich für gewählte Apps wie osu! von selbst ein.")),
        ("square.stack.3d.up", L("Kurzbefehle"), L("Verbinden, Werkzeuge und Tablett-Modus aus Kurzbefehle, Siri und Kontrollzentrum.")),
        ("thermometer.medium", L("Hitzeschutz"), L("Wird der Mac heiß, drosselt sich der Stream – abgedunkelt pausiert er ganz.")),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    UltraBadge("sparkles", size: 64)
                        .symbolEffect(.bounce, value: shown)
                        .scaleEffect(shown ? 1 : 0.6)
                    Text(L("Neu in %@", Self.version))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            card(item)
                                .opacity(shown ? 1 : 0)
                                .offset(y: shown ? 0 : 16)
                                .animation(Ultra.bouncy.delay(0.08 + Double(i) * 0.035), value: shown)
                        }
                    }
                    Text(L("Alles Weitere steht im Menü oben rechts unter „Mehr“: Gesten & Kürzel und die Einstellungen."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .mask {
                // Cards fade out under the button instead of running into it.
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 130)
                }
                .ignoresSafeArea()
            }
            Button {
                Self.markSeen()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Text(L("Los geht's"))
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(UltraProminent())
            .padding(.bottom, 30)
        }
        .preferredColorScheme(.dark)
        .onAppear { withAnimation(Ultra.bouncy) { shown = true } }
        .onDisappear { Self.markSeen() }   // swiped away counts as seen too
    }

    private func card(_ item: (String, String, String)) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.0)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Brand.slateDeep)
                .frame(width: 40, height: 40)
                .background(Ultra.accentFill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.1).font(.headline)
                Text(item.2).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .ultraGlass(Ultra.shape(Ultra.cardRadius))
        .accessibilityElement(children: .combine)
    }
}
