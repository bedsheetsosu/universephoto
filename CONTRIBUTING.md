# Mitwirken an UniverseStudio

Schön, dass du etwas beitragen willst! Es gibt zwei harte Regeln.

## 1. Keine KI in Beiträgen

Pull Requests werden **nur angenommen, wenn keine KI beteiligt war**. Code, Texte,
Commit-Messages und Beschreibungen müssen von einem Menschen geschrieben sein — nicht
von einem LLM oder KI-Assistenten (ChatGPT, Claude, Copilot, Cursor, Gemini und
Ähnliches) erzeugt oder wesentlich mitgeschrieben.

Jeder Pull Request muss die Erklärung im PR-Template enthalten und bestätigen. Ein PR
ohne diese Bestätigung — oder bei dem sich zeigt, dass doch KI im Spiel war — wird
geschlossen, nicht gemergt.

*(Hinweis: Diese Regel gilt für externe Beiträge. Commits der Maintainer auf `main`
können KI-gestützt sein und sind entsprechend gekennzeichnet.)*

## 2. Lizenz des Beitrags

Mit dem Einreichen eines Beitrags stimmst du zu, dass er unter der
[UniverseStudio License (USL) 1.0](LICENSE) steht — source-available, nicht verkaufbar,
Forks müssen offen bleiben. Siehe die Lizenz für die genauen Bedingungen.

## Ablauf

1. Issue aufmachen oder ein bestehendes nehmen, kurz beschreiben, was du vorhast.
2. Fork, Branch, Änderung — klein und fokussiert.
3. `swift test` läuft grün, Mac-App baut (`./scripts/build-app.sh`).
4. PR aufmachen, das Template vollständig ausfüllen, **beide** Haken setzen.
