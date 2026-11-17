# Reproduzierbarer Renderer-Benchmark

Stand: 17. November 2026. Messung auf dem Entwicklungs-Mac mit Äbbl™ M5, macOS 27.0.1, Swift 6.4.2, Debug-Build.

Ausführen:

```sh
swift test --filter RendererPerformanceTests/testFixed1200x800PreviewBenchmark
```

Die feste Testszene enthält 1200 × 800 Pixel, vier Ebenen, insgesamt 80 Striche mit jeweils 64 Stiftpunkten und einen laufenden Strich mit 100 Punkten auf der obersten Ebene. Nach dem Aufwärmen des Canvas-Ebenencaches werden zehn aktualisierte Vorschaubilder erzeugt. Der Test prüft zusätzlich die pixelgenaue Gleichheit mit dem Rendern ohne Cache.

Im vollständigen Testlauf am 17. November 2026 wurden gemessen:

| Messgröße | Zeit |
|---|---:|
| Median der zehn warmen Renderaufrufe | 2,768 ms |
| 90. Perzentil (Nearest Rank) | 3,256 ms |
| Maximum | 3,306 ms |

Die Werte messen die Dauer der synchronen Compositing-Aufrufe. Sie sind keine Display-FPS, keine Eingabelatenz und kein Nachweis für große Produktionsdokumente. Ergebnisse ändern sich mit Geräteauslastung, Dokumentinhalt, Filtern und Masken. Ein isolierter Renderer-Testlauf derselben Szene ergab zuvor 6,046 ms Median; daraus ist die normale Streuung der Entwicklungsumgebung sichtbar.

Die Vorschau nutzt einen pro Canvas gehaltenen Cache isolierter Ebenen mit höchstens 64 MiB Bildspeicher. Änderungen an Deckkraft, Mischmodus und Transformation verwenden das bestehende Ebenenbild weiter. Beim Zeichnen auf einer Ebene ohne Masken oder Anpassungen werden die bereits abgeschlossenen Striche als Bitmap kopiert und nur der neue Strich gerastert. Der Renderer verbindet Druckradien durch Segmentsilhouetten und rundet die tatsächlich gelieferten Stiftpunkte ab. Der ursprüngliche Algorithmus erzeugte zahlreiche interpolierte Ellipsen und war bei derselben synthetischen Szene erheblich langsamer.

Unverändert teuer bleiben große Bildpuffer, Masken- und Filtervorschauen sowie der vollständige Erstaufbau. Die Darstellung verwendet Core Graphics und Core Image; eine eigene Metal-Tile-Engine ist noch nicht implementiert.
