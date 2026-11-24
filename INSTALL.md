# Installation und Entwicklung

## Gebaute Anwendung starten

`UniversePhoto.app` liegt neben dem Projektordner `UniversePhoto`. Im Finder doppelt anklicken oder aus dem Projektordner starten:

```sh
open build/UniverseStudio.app
```

Die lokale Entwicklungs-App wird ad hoc signiert. Eine notarierte öffentliche Veröffentlichung wurde nicht erstellt.

## Aus dem Quelltext bauen

Benötigt werden macOS 15 oder neuer, Swift 6 und die macOS-Entwicklungswerkzeuge. Es werden keine externen Swift-Pakete, Konten oder API-Schlüssel benötigt.

```sh
./scripts/build-app.sh
```

Das Skript erstellt einen Release-Build, erzeugt das eigene App-Icon, legt das Bundle als `build/UniverseStudio.app` an und signiert es lokal. Es installiert nichts nach `/Applications` und verändert keine Systemeinstellungen. Der Quellcode kann auch direkt mit `swift run` gestartet werden.

Automatisierte Prüfung:

```sh
swift build
swift test
node Tests/PluginBridge/bridge.test.cjs
```

Der feste Renderer-Benchmark kann separat mit `swift test --filter RendererPerformanceTests/testFixed1200x800PreviewBenchmark` ausgeführt werden. Aufbau, Messwerte und Aussagegrenzen stehen in `PERFORMANCE.md`.

## Erste Zeichnung

1. Neues Dokument über `⌘N` erstellen und Breite/Höhe wählen. Die Bildfläche ist transparent; das Schachbrett zeigt ihre leeren Bereiche.
2. Im Arbeitsbereich **Simple** Pinsel auswählen, Farbe und Größe einstellen und auf der Leinwand zeichnen. **Photo** zeigt alle Werkzeuge und die erweiterten Eigenschaften.
3. Im Inspector Ebenen ergänzen und deren Sichtbarkeit, Deckkraft oder Mischmodus einstellen. `⌘Z` und `⌘⇧Z` führen Bearbeitungen zurück beziehungsweise wieder aus.
4. Mit `⌘S` als `.universephoto` speichern. Nur dieses native Format erhält alle implementierten Ebenen-, Masken- und Animationsdaten.
5. **Animate** öffnet die Timeline: Frame duplizieren oder leeren Frame erzeugen, zeichnen und die Wiedergabe starten. Der Export bietet PNG-Sequenz, GIF oder MP4.

Der Einstellungen-Knopf oben rechts öffnet Darstellung, Sprache, API-Schalter und **Wiederherstellung**. Nach 1,5 Sekunden ohne weitere Bearbeitung werden geänderte Dokumente als Wiederherstellungskopie unter `~/Library/Application Support/UniversePhoto/Recovery/` gesichert. Dort geladene Dokumente erneut an einem gewählten Ort speichern.

## Optional: UniversePen-Eingabe

1. Die bestehende UniversePen-Developer-API im UniversePen-Mac-Programm selbst einschalten.
2. In UniversePhoto die Einstellungen öffnen und den **API**-Schalter aktivieren. Erst jetzt verbindet sich die App mit `127.0.0.1:47800`.
3. Den Live-Status beachten. Bei deaktivierter oder nicht erreichbarer API bleiben Maus und normale Grafiktabletts nutzbar; der Adapter versucht nach Abbrüchen erneut zu verbinden.
4. Zum Beenden den Schalter ausschalten. UniversePhotos Schalter verändert die API-Freigabe in UniversePen nicht.

Die direkte API-Route ist auf das primäre iPad begrenzt. Bei zusätzlichen UniversePen-iPads den direkten Adapter ausschalten und native Eingabe verwenden. Der geprüfte Entwicklungsstand hat eine reale API-Verbindung mit verbundenem iPad aufgebaut; Pencil-Striche auf der tatsächlichen App sind ein gesonderter Hardwaretest.

## Optional: UniversePhoto Bridge

Die [Plugin-Dokumentation](UniversePhotoBridge/README.md) beschreibt alle 31 Aktionen. Den Ordner `UniversePhotoBridge` nach `~/Library/Application Support/UniversePen/Plugins/` kopieren und im UniversePen-Pluginfenster aktivieren. Einen gleichnamigen vorhandenen Ordner zuerst erhalten und die Versionen vergleichen; keine bestehenden Plugin-Dateien blind überschreiben.

Anschließend Aktionen in UniversePen der Shortcut-Leiste, dem Radialmenü oder Gesten zuordnen. UniversePhoto muss im Vordergrund sein. Shortcut-Ausgabe verwendet UniversePens vorhandene Bedienungshilfenberechtigung. Die Bridge benötigt die Developer-API nicht und verändert keine Benutzerprofile.
