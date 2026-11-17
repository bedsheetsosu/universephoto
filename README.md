# UniversePhoto™ 0.2

Kostenlose, quelloffene macOS-Anwendung zum Zeichnen, zur Bildbearbeitung und für Frame-Animation. UniversePhoto läuft eigenständig und lokal; UniversePen ist optional. Dieser Entwicklungsstand liefert eine benutzbare Grundlage mit neuem UltraUI und klar begrenztem Funktionsumfang.

## Start

Die gebaute App liegt nach dem Bauen unter `build/UniversePhoto.app`. Zum eigenen Bauen werden macOS 14 oder neuer und Swift 6 benötigt:

```sh
./scripts/build-app.sh
open build/UniversePhoto.app
```

Für Entwicklung und Tests:

```sh
swift run
swift test
node Tests/PluginBridge/bridge.test.cjs
```

Details: [Installation](INSTALL.md), [Architektur](ARCHITECTURE.md), [Gestaltungsreferenzen](DESIGN.md), [Renderer-Messung](PERFORMANCE.md).

## Implementiert

- **UltraUI:** schwebende Werkzeugpalette, Dokument-Tabs mit Änderungsanzeige, kontextbezogene Optionen, Inspector-Karten, Befehlssuche und Simple/Photo/Animate. Dunkler, heller und Systemmodus, fünf Akzentfarben sowie Deutsch/Englisch. Inspector und Timeline sind einblendbar und skalierbar; Werkzeugpositionen lassen sich über das Kontextmenü ändern.
- **14 Werkzeuge:** Pinsel, Radierer, Pipette, Ebenenverschiebung, Rechteckauswahl, Ellipsenauswahl, Lasso, Flächenfüllung, Farbverlauf, Text, Rechteck, Ellipse, Linie und Handwerkzeug.
- **Zeichnen:** variabler Druckradius, Neigung und Stiftrotation bei vorhandenen Gerätedaten, Deckkraft, Glättung und JSON-Import/-Export eigener Pinselvorgaben. Der Radierer entfernt Alpha auf der aktiven Ebene.
- **Leinwand:** transparenter Schachbretthintergrund, Pan, Zoom, Drehung, Spiegelansicht, Lineale, Raster und optionales 25-Pixel-Snapping. Anzeige und Eingabe verwenden dieselbe invertierbare Transformation.
- **Ebenen:** Sichtbarkeit, Sperre, Reihenfolge, Duplizieren, Zusammenführen, Deckkraft, Transformation und sechs Mischmodi: Normal, Multiply, Screen, Overlay, Darken, Lighten. Bearbeitbare Ebenenmasken verwenden schwarze Striche zum Verbergen und weiße zum Wiederherstellen.
- **Nichtdestruktive Korrekturen:** Helligkeit, Kontrast, Sättigung, Belichtung, Gauß-Weichzeichner und Invertieren. Schwarzweiß setzt die Sättigung auf null.
- **Dokumente:** Undo/Redo, atomisches Speichern, eingebettete Bilddaten, Formatversion 2 mit aktivem Animationsframe sowie Laden alter Version-1-Projekte. Wiederherstellungskopien werden nach 1,5 Sekunden ohne weitere Bearbeitung geschrieben.
- **Animation:** ganze Ebenenstapel als Frames, leere/duplizierte/gelöschte Frames, Vorschaubilder, Framewechsel, einstellbare FPS, Schleifenwiedergabe und vorheriger Frame als Onion Skin.
- **Dateien:** PNG-, JPEG- und TIFF-Import als Ebene; PNG-/JPEG-/TIFF-Export; transparente PNG-Sequenz; GIF und H.264-MP4 ohne Ton.

Die Flächenfüllung füllt die aktive Ebene beziehungsweise Auswahl; sie ist kein toleranzbasierter Farbeimer. Auswahlen begrenzen nachfolgende Zeichenoperationen. Sie verschieben oder kopieren keine vorhandenen Pixel. Text wird mit seinem Textinhalt im Dokument gespeichert; eine nachträgliche Textobjekt-Auswahl ist noch nicht vorhanden.

## UniversePen

Die Anwendungseinstellungen bieten einen optionalen Eingabeadapter für die vorhandene lokale Developer-API auf `127.0.0.1:47800`. Erst der Schalter in UniversePhoto startet die Verbindung. Die API muss zuvor vom Nutzer in UniversePen aktiviert worden sein. Der Adapter prüft das Protokoll, zeigt den Status und verbindet sich nach Abbrüchen neu.

Globale Bildschirmkoordinaten werden auf die tatsächliche, gezoomte und gedrehte Leinwand abgebildet. Bereits von UniversePen injizierte Pencil-Ereignisse werden anhand seines vorhandenen Tablet-Device-Identifiers unterdrückt, solange das API-Abonnement aktiv ist. Maus und gewöhnliche Grafiktabletts bleiben nutzbar. Neigung, Rotation und Hover werden übernommen, soweit Samples diese Daten enthalten. Gesten-, Touch- und Tastaturkopien werden nicht erneut abgespielt, weil UniversePen die konfigurierten Aktionen bereits selbst ausführt.

Die direkte API-Route gilt zunächst für das primäre iPad. Zusätzliche iPads verwenden im aktuellen UniversePen-Host denselben nativen Device-Identifier, liefern aber keine eigenen Developer-API-Pencil-Samples; für diesen gleichzeitigen Betrieb den direkten Adapter ausschalten und native Eingabe verwenden.

[UniversePhoto Bridge](UniversePhotoBridge/README.md) registriert 31 Aktionen für Shortcut-Leiste, Radialmenü und zuweisbare Gesten. Das Plugin prüft die Vordergrund-App und sendet dokumentierte Tastenkürzel. Es verändert keine Profile und besitzt keinen Netzwerk- oder Dateizugriff. Ein bidirektionaler Zustandskanal ist nicht implementiert.

## Wichtige Kürzel

| Aktion | Kürzel |
|---|---|
| Pinsel / Radierer / Pipette | B / E / I |
| Verschieben / Rechteckauswahl / Lasso | V / M / L |
| Pinselgröße / Deckkraft | [ und ] / , und . |
| Nächste Palettenfarbe | X |
| Undo / Redo | ⌘Z / ⌘⇧Z |
| Neue / duplizierte Ebene | ⌘⇧N / ⌘J |
| Spiegeln / Einpassen | H / ⌘0 |
| Frame duplizieren | ⇧F |
| Frame zurück / weiter | ⌥← / ⌥→ |
| Onion Skin / Wiedergabe | ⌥O / Leertaste |
| Befehlssuche | ⌘⇧P |

Die vollständige Bridge-Tabelle steht in der Plugin-Dokumentation. Tastenkürzel sind derzeit fest vorgegeben.

## Grenzen und Nachweise

Zuletzt bestanden 31 Swift-Tests. Sie prüfen unter anderem ältere Dokumente, echte Speicher-/Ladeoperationen, Undo/Redo, Masken, Mischmodi, Transformationen, Auswahl-Clips, Export und API-Protokoll. Der JavaScript-Test prüft die 31 Plugin-Aktionen und Vordergrundsperre. Diese Prüfungen ersetzen keine manuelle Interaktionsprüfung. Der reale API-Verbindungs- und Abonnementtest mit verbundenem iPad war erfolgreich; echte Pencil-Striche und iPad-Plugin-Auslösung wurden dabei noch nicht beobachtet.

Der Renderer verarbeitet 8-Bit-sRGB/RGBA über Core Graphics und Core Image mit einem Ebenencache. Der dokumentierte Benchmark ist keine FPS- oder Eingabelatenzmessung. Filter- und Maskenvorschauen können bei großen Dokumenten teuer werden; eine eigene Metal-Tile-Engine ist noch offen.

PNG und TIFF erhalten Alpha, JPEG und MP4 werden über Weiß ausgegeben. Bildexporte sind flach und enthalten keine Ebenen; dafür das native Format behalten. Importbilder werden nach sRGB normalisiert und auf die Dokumentfläche abgebildet. TIFF-Mehrseitenbilder und animierte Importbilder werden ausdrücklich abgewiesen. GIF besitzt eine begrenzte Palette und gerundetes Frame-Timing. MP4 benötigt gerade Bildmaße; exportiert wird in Dokumentauflösung.

Noch offen sind Ebenengruppen, Clipping-Masken, Pixeltransformation von Auswahlen, Zauberstab/Flood Fill, Stempel und Retuschewerkzeuge, Gradationskurven, CMYK/HDR, Audio, unabhängige Animationstracks, Keyframe-Interpolation, Cutout-Rigs, Lip-Sync, HEVC, PSD, OpenRaster, WebP und SVG. Vollständige Photoshop-/PSD-Kompatibilität wird nicht beansprucht. Sinnvolle nächste Schritte sind Audio/Timeline, Auswahl-Pixeloperationen und eine gekachelte Rasterengine.

## Lizenz

GPL-3.0-or-later, vollständiger Text in [LICENSE](LICENSE), Hinweise in [COPYING.md](COPYING.md). Das Projekt verwendet ausschließlich native Systemframeworks und keine externen Swift-Pakete, kostenpflichtigen APIs, Telemetrie oder Cloud-Dienste. UniversePen bleibt ein eigenständiges Projekt; dessen SDK-Dokumentation ist MIT-lizenziert.
