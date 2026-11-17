# Architektur

UniversePhoto bleibt ein einziges Swift-Package mit klaren Verantwortungsbereichen und ohne externe Paketabhängigkeiten. Die Anwendung benötigt weder UniversePen noch einen Cloud-Dienst.

| Datei / Bereich | Verantwortung |
|---|---|
| `DocumentCore.swift` | Codable-/Sendable-Dokument, Ebenen, Striche, Masken, Korrekturen und Transformationen; Werkzeugdefinitionen und gemeinsame Leinwandgeometrie. |
| `Studio.swift` | Dokument-Tabs, Bearbeitungszustand, Undo/Redo, Ebenenaktionen, Frame-Schnappschüsse, Wiedergabe, Dateidialoge, Validierung und Wiederherstellung. |
| `RenderingEngine.swift` | Isolierte Ebenenpuffer, Alpha-Radierer, Druckpinsel, Formen, Text, Auswahl-Clips, Masken, sechs Mischmodi und nichtdestruktive Core-Image-Korrekturen. Canvas-Ebenencache mit begrenztem Speicher. |
| `CanvasView.swift` | AppKit-Eingabe, Vorschau, Schachbrett, Lineale/Raster, Auswahlpfade und inverse Koordinatenabbildung für native und API-Stifteingabe. |
| `ImportExport.swift` | ImageIO-Import/-Export, EXIF-Orientierung und sRGB-Normalisierung, PNG-Sequenz, GIF sowie AVFoundation-H.264-MP4. |
| `UniversePenAdapter.swift` | Opt-in-Verbindung, API-v1-Prüfung, JSON-Lines-Decoder, Status, begrenzter Puffer, Abbruch und Wiederverbindung. |
| `UniversePhotoBridge/` | Separates JavaScript-Plugin: ausschließlich dokumentierte UniversePen-Aktionen und Tastenkürzel. |
| `PhotoDesign.swift` | Eigene Palette, Oberflächen, Materialien, Lichtkanten, Animationen und Komponenten. Die lesend untersuchten Gestaltungsreferenzen stehen in `DESIGN.md`. |
| `WorkspaceUI.swift`, `InspectorPanel.swift`, `TimelinePanel.swift` | Arbeitsbereiche, Dokument-/Werkzeugsteuerung, Eigenschaften, Farben, Pinsel, Korrekturen, Verlauf und Timeline. |
| `UniversePhotoApp.swift` | Nativer App-Einstieg, Menübefehle, Dokumentöffnung und Beenden mit Änderungsprüfung. |

## Dokument und Persistenz

`.universephoto` ist ein versioniertes JSON-Dokument. Version 2 ergänzt Ebeneneigenschaften, eingebettete Rasterbilder, Maskenstriche, Korrekturen, Transformationen, FPS und den aktiven Frame. Fehlende neue Eigenschaften erhalten beim Laden von Version 1 kompatible Standardwerte. Ebenen bleiben ein geordneter flacher Stapel; Gruppen und Clipping-Masken sind noch nicht vorhanden.

Ein Frame speichert einen ganzen Ebenenstapel. Der aktuelle Arbeitsstapel wird vor Dokument-Snapshot und Framewechsel in den aktiven Frame übernommen. Das ist eine Frame-Animation mit Ebenen innerhalb der Zeichnungen, noch keine unabhängige Belichtungs-/Keyframe-Timeline pro Ebene.

Speichern verwendet atomisches Dateischreiben. Native Dokumente erhalten Ebenen und eingebettete Bilddaten; Bild- und Videoexporte sind ausdrücklich flach. Nach 1,5 Sekunden ohne weitere Bearbeitung wird eine Wiederherstellungskopie unter `~/Library/Application Support/UniversePhoto/Recovery/` geschrieben. Wiederherstellen erfolgt über die Anwendungseinstellungen. Änderungen unmittelbar vor einem Absturz können dem Schreibintervall entsprechend fehlen.

## Rendern und Eingabe

Dokumentkoordinaten sind Pixel mit Ursprung oben links. `CanvasGeometry` beschreibt Skalierung, Pan, Rotation und Spiegelung; Anzeige und Eingabe verwenden dieselbe Transformation beziehungsweise deren Inverse. Zusätzliche Ebenentransformationen werden für das Zeichnen auf die lokale Ebene zurückgerechnet.

Der Referenzrenderer arbeitet mit 8-Bit-sRGB/RGBA. Eine Ebene wird isoliert gerastert, damit der Radierer nur ihre eigene Transparenz löscht. Masken und Anpassungen bleiben im Modell separat. Der Canvas hält gerasterte Ebenen in einem begrenzten Cache; Eigenschaften wie Deckkraft und Transformation können vorhandene Ebenenbilder wiederverwenden. Core Image verwendet seinen eigenen Framework-Renderer. Eine eigene Metal- oder Tile-Pipeline wird nicht behauptet; reproduzierbare Messungen stehen in `PERFORMANCE.md`.

Stiftpunkte enthalten Druck und optionale Neigung/Rotation. Das AppKit-Eingabegerät liefert normale Mausereignisse oder Tablet-Samples. Der optionale UniversePen-Adapter verarbeitet TCP und JSON auf einer eigenen seriellen Queue und übergibt typisierte Samples an den Main Actor. Export und aufwendige Export-Renderarbeit laufen in Hintergrundtasks. Die interaktive Vorschau arbeitet weiterhin synchron und ist bei großen Masken-/Filterdokumenten begrenzt.

## UniversePen-Grenze

Die Anwendung verbindet sich ausschließlich nach Betätigung ihres API-Schalters mit `127.0.0.1:47800`; sie aktiviert weder die Developer-API noch andere UniversePen-Einstellungen. Erst auf den geprüften API-v1-Gruß folgt ein `input`-/`status`-Abonnement. Verbindungsabbrüche löschen unvollständige Protokollnachrichten und angefangene Remote-Striche; Wiederverbindung folgt nach zwei Sekunden.

API-Screen-Koordinaten beschreiben globale Mac-Punkte mit oberem Ursprung am Hauptdisplay. Der Canvas rechnet diese zunächst ins Fenster und danach in das Dokument um. Während eines bestätigten API-Abonnements erkennt er bereits injizierte UniversePen-Pencil-Ereignisse am vorhandenen Device-Identifier `0x7AFE1`. Der aktuelle UniversePen-Host liefert API-Pencil-Samples nur für das primäre iPad. Zusätzliche iPads mit identischem nativen Identifier benötigen daher den nativen Eingabepfad bei ausgeschaltetem direktem Adapter.

Das Plugin registriert 31 `up.action`-Einträge und verwendet `up.frontApp`, `up.on`, `up.shortcut`, `up.toast` und `up.log`. Es verändert keine Profile und öffnet keine App-Verbindungen. Gesten werden über UniversePens bestehende Zuordnung auf diese Aktionen gelegt. API-Kopien von Gesten, Touch und Tastatur werden nicht nochmals abgespielt.

Ein zukünftiger bidirektionaler Zustandskanal ist ein eigener, noch nicht implementierter Vorschlag: explizite Nutzerfreigabe, geprüfte Anwendungsidentität, typisierte und begrenzte Nachrichten sowie getrennte Lese-/Aktionsberechtigungen. Die bestehende Plugin-Sandbox wird dafür nicht verändert.

## Prüfung

Tests decken Dokumentkompatibilität und Persistenz, Undo/Redo, Ebenen, Renderpixel, Masken/Mischmodi, Koordinaten, Animation/Export und Protokoll-Framing ab. Die Bridge hat einen separaten JavaScript-Test. Visuelle App-Prüfung und echte Hardwareeingabe werden als eigene Nachweise behandelt; ein erfolgreicher TCP-Verbindungscheck belegt keine tatsächlich gezeichneten Pencil-Striche.
