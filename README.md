# UniversePhoto™ 0.23

Kostenlose, quelloffene macOS-Anwendung zum Zeichnen, zur Bildbearbeitung und für Frame-Animation. UniversePhoto läuft eigenständig und lokal; UniversePen ist optional. Dieser Entwicklungsstand liefert eine benutzbare Grundlage mit neuem UltraUI und klar begrenztem Funktionsumfang.

## Start

Die gebaute App liegt nach dem Bauen unter `build/UniversePhoto.app`. Zum eigenen Bauen werden macOS 15 oder neuer und Swift 6 benötigt:

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

- **UltraUI im UniversePen-Stil:** Mint-Akzent und Indigo-Hintergrund wie UniversePen (dieselben Akzent-Presets), optional fließender Mesh-Hintergrund mit einstellbarem Tempo (steht bei „Bewegung reduzieren“ still), schwebende Werkzeugpalette, Dokument-Tabs mit Änderungsanzeige, kontextbezogene Optionen, Inspector-Karten, Befehlssuche und Simple/Photo/Animate. Dunkler, heller und Systemmodus, fünf Akzentfarben sowie Deutsch/Englisch. Inspector und Timeline sind einblendbar und skalierbar; Werkzeugpositionen lassen sich über das Kontextmenü ändern.
- **21 Werkzeuge:** Pinsel, Radierer, Pipette, Ebenenverschiebung, Rechteckauswahl, Ellipsenauswahl, Lasso, Zauberstab, Flächenfüllung, Farbeimer, Farbverlauf, Kopierstempel, Reparaturpinsel, Wischfinger, Abwedler/Nachbelichter, Weichzeichner/Scharfzeichner, Text, Rechteck, Ellipse, Linie und Handwerkzeug.
- **Retusche (0.5):** Kopierstempel (S) und Reparaturpinsel (J): ⌥-Klick setzt die Quelle, ein Fadenkreuz zeigt beim Malen, woher kopiert wird; „Ausgerichtet“ behält den Abstand über mehrere Striche, „Alle Ebenen“ kopiert aus dem sichtbaren Bild. Der Reparaturpinsel übernimmt die Struktur der Quelle mit Helligkeit und Farbe des Ziels (Quelle + Weichzeichnung(Ziel) − Weichzeichnung(Quelle)). Wischfinger (F) schiebt Farbe mit weicher Kante live über die Ebene. Abwedler/Nachbelichter (O) hellt auf oder dunkelt ab, Weichzeichner/Scharfzeichner (Y) wirkt nur unter dem Pinsel; beide mit Stärke und ohne neue Pixel auf leeren Flächen. Alle Retuschestriche sind je ein Undo-Schritt; Stempel, Reparatur und Wischfinger werden beim Loslassen zu Bitmap-Strichen.
- **Farbeimer und Zauberstab (0.3):** Toleranz 0–255, nur benachbarte oder alle ähnlichen Pixel, aktive Ebene oder alle Ebenen. Der Farbeimer legt seine Füllung als eigenen Bitmap-Strich ab (ein Undo-Schritt, Striche bleiben erhalten) und deckt Kantenpixel mit ab. Der Zauberstab erzeugt eine Pixelauswahl; ⇧ fügt hinzu, ⌥ zieht ab. Auswahl → Alles auswählen (⌘A), Auswahl umkehren (⇧⌘I). Ebenen → Ebene rastern.
- **Zeichnen:** variabler Druckradius, Neigung und Stiftrotation bei vorhandenen Gerätedaten, Deckkraft, Glättung und JSON-Import/-Export eigener Pinselvorgaben. Der Radierer entfernt Alpha auf der aktiven Ebene.
- **Leinwand:** transparenter Schachbretthintergrund, Pan, Zoom, Drehung, Spiegelansicht, Lineale, Raster und optionales 25-Pixel-Snapping. Anzeige und Eingabe verwenden dieselbe invertierbare Transformation.
- **Zwischenablage und schwebende Auswahl (0.4):** Ausschneiden (⌘X), Kopieren (⌘C), auf eine Ebene reduziert kopieren (⇧⌘C), Einfügen (⌘V; eigene Kopien landen an derselben Stelle, fremde Bilder mittig und bei Bedarf verkleinert), Auswahl löschen, Ebene durch Kopie (⌘J) oder Ausschneiden (⇧⌘J). Das Verschieben-Werkzeug hebt eine Auswahl auf eine eigene Ebene und bewegt sie. In Textfeldern behalten ⌘X/⌘C/⌘V/⌘A ihre normale Bedeutung.
- **Schnittmasken (0.4):** Ebenen → Schnittmaske (⌥⌘G) oder „Schneiden“ in den Eigenschaften: die Ebene zeigt sich nur dort, wo die nächste nicht beschnittene Ebene darunter Pixel hat – auch wenn diese verschoben, gedreht oder skaliert ist. Eine ausgeblendete Basis blendet ihre beschnittenen Ebenen mit aus.
- **Frei transformieren und Ausrichten (0.8):** Ebenen → Frei transformieren (⌘T) legt einen Rahmen mit Anfassern um die Pixel der aktiven Ebene: Ecken skalieren, innen ziehen verschiebt, außen ziehen dreht (⇧ rastet auf 15° ein) – immer um die Mitte des Inhalts; ↩ oder Esc beendet. Transformation zurücksetzen. An Leinwand ausrichten: linke/rechte/obere/untere Kanten, horizontale und vertikale Mitten, auch für mehrere gewählte Ebenen. Text-Werkzeug mit Schriftwahl (alle installierten Schriftfamilien) und Fett.
- **Ebenengruppen und Mehrfachauswahl (0.7):** In der Ebenenliste wählt ⌘-Klick weitere Ebenen, ⇧-Klick einen Bereich. Ebenen gruppieren (⌘G) sammelt sie in Reihenfolge in einem Ordner mit Auge, Auf-/Zuklappen, Name und Gruppen-Deckkraft; Gruppierung aufheben (⇧⌘G). Klick auf den Gruppenkopf wählt alle Ebenen der Gruppe, das Verschieben-Werkzeug bewegt alle gewählten Ebenen gemeinsam. Gruppen gelten für Leinwand, Export, Zwischenablage, Zauberstab, Stempel und Timeline. Die Gruppen-Deckkraft wirkt je Ebene (wie „Hindurchwirken“, bei überlappenden Ebenen leicht anders als eine flach zusammengesetzte Gruppe); verschachtelte Gruppen gibt es noch nicht.
- **Verflüssigen (0.23):** Werkzeug Q schiebt Pixel beim Ziehen mit, wie ein Finger in nasser Farbe, ohne Farben zu verschmieren (Größe und Stärke in der Optionsleiste). Live auf der aktiven Ebene; beim Loslassen wird die Ebene zum verschobenen Bild (ihre Striche werden dabei gerastert, ein Rückgängig stellt alles wieder her). Grenzen: nur Schieben (noch kein Strudel/Aufblasen/Zusammenziehen), Auswahlen begrenzen es nicht, nicht auf Einstellungsebenen.
- **Hilfslinien (0.22):** Aus dem oberen Lineal eine waagerechte, aus dem linken eine senkrechte Hilfslinie ziehen; mit dem Verschieben-Werkzeug lassen sie sich greifen und versetzen, vom Bild gezogen verschwinden sie. Ansicht → Hilfslinien einblenden (⌘;), An Hilfslinien ausrichten (⇧⌘;), fixieren, „Neue Hilfslinie …“ mit Pixelposition, „Hilfslinien aus Auswahl“ und löschen. Formen, Auswahlen, Verläufe, Text und Verschieben rasten auf Hilfslinien, Bildränder und Bildmitte ein (6 Bildschirmpunkte); Pinsel und Retusche rasten bewusst nicht ein. Hilfslinien werden im Projekt gespeichert und folgen Drehen, Spiegeln, Freistellen und Bildgröße.
- **Ebenen suchen und einzeln exportieren (0.21):** Ab vier Ebenen filtert ein Suchfeld die Ebenenliste nach Namen und Gruppen; „Text“, „Einstellung“ und „Ausgeblendet“ finden die passenden Ebenen. Ablage → „Ebenen als Dateien exportieren …“ schreibt jede sichtbare Pixelebene als eigene PNG in Dokumentgröße (mit Transformation, Stil, Korrekturen; ohne Deckkraft und Mischmodus; Einstellungsebenen nicht). „Auswahl exportieren …“ speichert den sichtbaren Inhalt der Auswahl, auf ihren Rahmen zugeschnitten und auf ihre Form maskiert.
- **Weißer Hintergrund:** Neue Dokumente bekommen standardmäßig eine weiße Ebene „Hintergrund“ unter der Zeichenebene (gemalt wird darüber). Im Dialog „Neues Dokument“ lässt sich „Transparent“ wählen; die Wahl bleibt gespeichert.
- **Transparenz fixieren und Protokoll (0.20):** Der Knopf in den Ebeneneigenschaften fixiert die Transparenz: Neue Striche, Füllungen und Texte landen nur auf vorhandenen Pixeln (Radierer und Masken bleiben frei). Im Protokoll springt ein Klick zu jedem Schritt; wiederherstellbare Schritte stehen gedimmt darüber und lassen sich ebenso anspringen.
- **Farben (0.19):** Hex-Eingabe (#RGB, #RRGGBB, #RRGGBBAA), Farben tauschen (X), Harmonien zur Vordergrundfarbe (Komplementär, Triade, Analog), die zehn zuletzt gemalten Farben und eigene Farbfelder (bis 24, bleiben über Neustarts erhalten; Rechtsklick entfernt).
- **Text (0.18):** Der Knopf neben dem Textfeld öffnet die Textoptionen: mehrzeiliger Text, linksbündig/zentriert/rechtsbündig um den Klickpunkt, Laufweite (−200 bis 800/1000 em), Zeilenabstand (0,6–3×), fett und kursiv (sofern die Schrift einen solchen Schnitt hat). Alte Texte bleiben unverändert.
- **Einstellungsebenen (0.17):** Ebenen → Neue Einstellungsebene (⌥⌘J) legt eine Ebene ohne eigene Pixel an: Ihre Korrekturen, Kurven und Smartfilter (Korrekturen-Tab) wirken auf alles darunter, nicht auf Ebenen darüber. Malen auf ihr malt ihre Maske (Schwarz verbirgt, Weiß zeigt), die Deckkraft schwächt den Effekt ab. Grenzen: Einstellungsebenen lassen sich nicht zusammenführen oder rastern, Schnittmasken auf sie wirken nicht, und im PSD-Export erscheinen sie als leere Ebene (der Effekt steckt dort nur im zusammengefügten Gesamtbild, nicht in den Ebenen).
- **Mehr Ebenenstile (0.16):** Schatten nach innen (Farbe, Deckkraft, Lichtwinkel, Abstand, Weichheit), Schein nach innen und Verlaufsüberlagerung (zwei Farben, Winkel, Deckkraft; über die eigenen Pixel der Ebene). Ältere Stile laden mit ausgeschalteten neuen Effekten.
- **Pinselspitzen (0.15):** Rund (wie bisher), Bleistift (harte Kante ohne Glättung), Marker (gleichmäßig breit, durchscheinend, ohne dunklere Überlappungen), Airbrush (weiche Tupfer, die sich aufbauen), Spray (Punkte, in der Mitte dichter) und Kreide (Körnung über einem blassen Strich). Druck steuert Größe und Fluss; Spray und Kreide sehen bei jedem Neuzeichnen gleich aus (aus der Strich-ID gesät). Die Spitzen gelten für den Pinsel, nicht für Radierer und Masken.
- **Formen (0.14):** Das Rechteck-Werkzeug zeichnet Rechteck, abgerundetes Rechteck (Eckenradius 2–200 px), Polygon (3–12 Ecken) und Stern (4–12 Zacken); Rechtecke, Formen und Ellipsen können gefüllt oder als Kontur gezeichnet werden. Das Linien-Werkzeug zeichnet auf Wunsch einen Pfeil. Alte Dokumente bleiben unverändert (Kontur).
- **Auswahl verändern (0.13):** Auswahl → Verändern: weiche Kante, erweitern, verkleinern, abrunden und Rand mit Radius 1–100 px (der letzte Wert bleibt gemerkt). „Farbbereich auswählen“ wählt alle sichtbaren Pixel nahe der Vordergrundfarbe (Toleranz wie beim Zauberstab). Weiche Auswahlen wirken weich beim Malen und Füllen; der Farbeimer füllt innerhalb einer weichen Auswahl hart.
- **Bild-Menü (0.12):** Bildgröße (⌥⌘I, verkettete Proportionen, 50/200 %), Arbeitsfläche (⌥⌘C) mit Neun-Punkt-Anker, auf Auswahl freistellen, transparente Pixel zuschneiden, Drehen um 90°/180°, Arbeitsfläche oder einzelne Ebene horizontal/vertikal spiegeln – für alle Ebenen aller Animationsframes, mit Undo. Ebenenmaske aus der Auswahl: „Auswahl einblenden“ zeigt nur die Auswahl, „Auswahl ausblenden“ versteckt sie (auch auf transformierten Ebenen). Ehrlich: Diese Geometrie-Befehle rastern Striche, Text und Transformation der Ebenen zu Pixeln; Deckkraft, Mischmodus, Korrekturen, Smartfilter, Stil und Schnittmaske bleiben live.
- **Smartfilter (0.11):** Im Korrekturen-Tab legt „Filter hinzufügen“ einen Filterstapel auf die aktive Ebene: Bewegungs- und Zoom-Unschärfe, Unscharf maskieren, Leuchten, Düster, Konturen finden, Strichzeichnung, Comic, Kristallisieren, Punktieren, Sechsecke, Kaleidoskop, Rastern, Strudel, Wölben, Zusammenziehen sowie zwölf Farblooks (Sepia, Wärmebild, Röntgen, Chrom, Noir …). Jeder Filter hat eine Stärke (wo sinnvoll), lässt sich ausblenden, umsortieren und entfernen; die Pixel bleiben unverändert und der Stapel wird im Projekt gespeichert. Der Verlauf kann jetzt linear, radial oder gespiegelt sein (Optionsleiste).
- **Ebenenstile (0.6):** Schlagschatten (Farbe, Deckkraft, Lichtwinkel, Abstand, Weichheit), Schein nach außen, Kontur außen und Farbüberlagerung – in den Eigenschaften der Ebene, nichtdestruktiv, sie folgen verschobenen, gedrehten und skalierten Ebenen. Beschnittene Ebenen richten sich weiter nach den Pixeln der Basis, nicht nach ihren Effekten.
- **Gradationskurven (0.4):** RGB und je ein Kanal Rot, Grün, Blau; Punkte ziehen, klicken fügt hinzu, aus dem Feld ziehen entfernt. Monotone Interpolation ohne Überschwinger, Histogramm der aktiven Ebene im Hintergrund, nichtdestruktiv.
- **Ebenen:** Sichtbarkeit, Sperre, Reihenfolge, Duplizieren, Zusammenführen, Rastern, Deckkraft, Transformation und 18 Mischmodi: Normal, Multiplizieren, Negativ multiplizieren, Ineinanderkopieren, Abdunkeln, Aufhellen, Farbig/Linear nachbelichten, Farbig/Linear abwedeln, Weiches/Hartes Licht, Differenz, Ausschluss, Farbton, Sättigung, Farbe, Luminanz. Bearbeitbare Ebenenmasken verwenden schwarze Striche zum Verbergen und weiße zum Wiederherstellen.
- **Nichtdestruktive Korrekturen:** Helligkeit, Kontrast, Sättigung, Belichtung, Farbton, Dynamik, Farbtemperatur, Farbstich, Tonwerte (Schwarz-/Weißpunkt, Mitteltöne), Schärfen, Rauschreduzierung, Vignette, Filmkorn, Tontrennung, Verpixeln, Gauß-Weichzeichner und Invertieren, dazu sechs Looks (Film, Lebendig, Noir, Kühl, Warm, Retro) als Startwerte. Ältere Dokumente laden die neuen Werte neutral.
- **Dokumente:** Undo/Redo, atomisches Speichern, eingebettete Bilddaten, Formatversion 2 mit aktivem Animationsframe sowie Laden alter Version-1-Projekte. Wiederherstellungskopien werden nach 1,5 Sekunden ohne weitere Bearbeitung geschrieben.
- **Animation:** ganze Ebenenstapel als Frames, leere/duplizierte/gelöschte Frames, Vorschaubilder, Framewechsel, einstellbare FPS, Schleifenwiedergabe und vorheriger Frame als Onion Skin.
- **Dateien:** PNG-, JPEG-, TIFF-, HEIC-, WebP-, BMP- und GIF-Import (Einzelbild) als Ebene; PNG-/JPEG-/TIFF-/HEIC-Export; transparente PNG-Sequenz; GIF und H.264-MP4 ohne Ton.
- **Photoshop-Dateien (0.9):** Öffnen (⌘O) liest PSD mit Ebenen – Namen, Deckkraft, Mischmodus, Sichtbarkeit, Schnittmasken, rohe und PackBits-komprimierte Daten; Dateien ohne Ebenen öffnen als ein Bild. Exportieren → „PSD · Ebenen“ schreibt jede Ebene so, wie sie aussieht (Transformation, Korrekturen, Maske und Ebenenstil eingerechnet) mit denselben Eigenschaften plus das zusammengesetzte Bild; macOS (Vorschau, Quick Look) liest die Dateien. Nicht übernommen werden Smartobjekte, Einstellungsebenen, editierbarer Text, Vektormasken, Effekte als Effekte und Gruppen als Ordner; 16/32-Bit, CMYK, PSB und ZIP-komprimierte Ebenen werden mit einer Meldung abgelehnt.

Die Flächenfüllung füllt die aktive Ebene beziehungsweise Auswahl; der Farbeimer füllt nach Toleranz. Pixelauswahl und Farbeimer arbeiten in Dokumentkoordinaten: auf verschobenen, gedrehten oder skalierten Ebenen passen sie erst nach „Ebene rastern“ und Zurücksetzen der Transformation genau. Auswahlen begrenzen nachfolgende Zeichenoperationen. Sie verschieben oder kopieren keine vorhandenen Pixel. Text wird mit seinem Textinhalt im Dokument gespeichert; eine nachträgliche Textobjekt-Auswahl ist noch nicht vorhanden.

## UniversePen

Die Anwendungseinstellungen bieten einen optionalen Eingabeadapter für die vorhandene lokale Developer-API auf `127.0.0.1:47800`. Erst der Schalter in UniversePhoto startet die Verbindung. Die API muss zuvor vom Nutzer in UniversePen aktiviert worden sein. Der Adapter prüft das Protokoll, zeigt den Status und verbindet sich nach Abbrüchen neu.

Globale Bildschirmkoordinaten werden auf die tatsächliche, gezoomte und gedrehte Leinwand abgebildet. Bereits von UniversePen injizierte Pencil-Ereignisse werden anhand seines vorhandenen Tablet-Device-Identifiers unterdrückt, solange das API-Abonnement aktiv ist. Maus und gewöhnliche Grafiktabletts bleiben nutzbar. Neigung, Rotation und Hover werden übernommen, soweit Samples diese Daten enthalten. Gesten-, Touch- und Tastaturkopien werden nicht erneut abgespielt, weil UniversePen die konfigurierten Aktionen bereits selbst ausführt.

Die direkte API-Route gilt zunächst für das primäre iPad. Zusätzliche iPads verwenden im aktuellen UniversePen-Host denselben nativen Device-Identifier, liefern aber keine eigenen Developer-API-Pencil-Samples; für diesen gleichzeitigen Betrieb den direkten Adapter ausschalten und native Eingabe verwenden.

**Seit 0.10:** Bei verbundener API zeigen Statusleiste und Einstellungen das iPad aus UniversePens Status (Name, USB/WLAN, Bildrate, Akku). Ein Knopf „iPad-Leiste für UniversePhoto“ legt – nur auf Klick – in UniversePen eine App-Kürzelleiste für `local.universephoto` an (Pinsel, Radierer, Pipette, Stempel, Rückgängig, Wiederholen, Pinselgröße, Hand, Einpassen), die auf dem iPad erscheint, solange UniversePhoto vorn ist; der Papierkorb daneben entfernt sie wieder. Antworten von UniversePen (auch Fehler wie „kein iPad“) werden angezeigt und trennen die Verbindung nicht. Im Pinsel-Tab gibt es eine eigene Druckkurve mit Vorlagen (Weich, Linear, Fest); sie gilt für den Pencil über die API und für jedes Grafiktablett. Der Gerätestatus ist per Test mit dem dokumentierten Format geprüft, live in UniversePhoto noch nicht gesehen.

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

Zuletzt bestanden 81 Swift-Tests (u. a. UniversePen-Status und -Antworten, Druckkurve, PSD hin und zurück und Lesbarkeit durch macOS, Transformieren, Ausrichten, Gruppen, Ebenenstile, Retusche, Farbeimer, Zauberstab, Auswahlmasken, Looks, Mischmodi, Schnittmasken, Kurven, Kopieren/Einfügen). Die Tests verwenden eine eigene Zwischenablage, nie die des Nutzers. Sie prüfen unter anderem ältere Dokumente, echte Speicher-/Ladeoperationen, Undo/Redo, Masken, Mischmodi, Transformationen, Auswahl-Clips, Export und API-Protokoll. Der JavaScript-Test prüft die 31 Plugin-Aktionen und Vordergrundsperre. Diese Prüfungen ersetzen keine manuelle Interaktionsprüfung. Der reale API-Verbindungs- und Abonnementtest mit verbundenem iPad war erfolgreich; echte Pencil-Striche und iPad-Plugin-Auslösung wurden dabei noch nicht beobachtet.

Der Renderer verarbeitet 8-Bit-sRGB/RGBA über Core Graphics und Core Image mit einem Ebenencache. Der dokumentierte Benchmark ist keine FPS- oder Eingabelatenzmessung. Filter- und Maskenvorschauen können bei großen Dokumenten teuer werden; eine eigene Metal-Tile-Engine ist noch offen.

PNG und TIFF erhalten Alpha, JPEG und MP4 werden über Weiß ausgegeben. Bildexporte sind flach und enthalten keine Ebenen; dafür das native Format behalten. Importbilder werden nach sRGB normalisiert und auf die Dokumentfläche abgebildet. TIFF-Mehrseitenbilder und animierte Importbilder werden ausdrücklich abgewiesen. GIF besitzt eine begrenzte Palette und gerundetes Frame-Timing. MP4 benötigt gerade Bildmaße; exportiert wird in Dokumentauflösung.

Noch offen sind verschachtelte Gruppen, freies Transformieren einer schwebenden Auswahl, inhaltsbasierte Füllung, CMYK/HDR, Audio, unabhängige Animationstracks, Keyframe-Interpolation, Cutout-Rigs, Lip-Sync, HEVC, OpenRaster und SVG. Vollständige Photoshop-Kompatibilität wird nicht beansprucht (siehe die Grenzen des PSD-Imports oben). Sinnvolle nächste Schritte sind Audio/Timeline, Auswahl-Pixeloperationen und eine gekachelte Rasterengine.

## Lizenz

GPL-3.0-or-later, vollständiger Text in [LICENSE](LICENSE), Hinweise in [COPYING.md](COPYING.md). Das Projekt verwendet ausschließlich native Systemframeworks und keine externen Swift-Pakete, kostenpflichtigen APIs, Telemetrie oder Cloud-Dienste. UniversePen bleibt ein eigenständiges Projekt; dessen SDK-Dokumentation ist MIT-lizenziert.
