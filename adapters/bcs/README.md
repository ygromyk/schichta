# schichta-bcs – Schichta → Projektron BCS

Eigenständiges Programm, das einen Schichta-Tag in die BCS-Tageserfassung bucht.
Schichta kennt BCS nicht; es ruft den Adapter nur als Shell-Hook auf und übergibt das
Tages-JSON auf stdin.

BCS hat dafür keine einfache API. Der Adapter bedient deshalb die Weboberfläche mit einem
unsichtbaren Chrome (puppeteer-core). Ablauf und Selektoren stammen aus
[projektron-bcs-cli](https://github.com/pgebert/projektron-bcs-cli) (Commit `8fd277ec`).

## Unterschiede zur CLI (bewusst sicherer)

| CLI | Adapter |
| --- | --- |
| `add` löscht den Tag immer vorher | belegter Tag wird **abgelehnt**, ersetzen nur mit `--replace` / `onExisting: "replace"` |
| unbekannte Tickets landen in einem fest verdrahteten Task | ohne Zuordnung **keine Buchung**, Fehler mit Hinweis |
| Ticketnummer wird nicht eingetragen | Ticket ins Feld `effortAttr1` (konfigurierbar), sonst vor die Beschreibung |
| Anwesenheit wird getippt (Ergebnis hängt von der Cursorposition ab) | Werte werden direkt gesetzt |
| kein Nachweis nach dem Speichern | Tag wird neu geladen und **gegengeprüft** |
| Passwort in `.env` | Passwort im **macOS-Schlüsselbund** |
| Schätzungen wie alles andere | als Schätzung markierte Einträge werden abgelehnt (`allowEstimated`) |

## Einrichtung

```bash
cd adapters/bcs && npm install              # nur puppeteer-core, nutzt dein installiertes Chrome
mkdir -p ~/.config/schichta-bcs-adapter
cp config.example.json ~/.config/schichta-bcs-adapter/config.json   # url, username, mapping anpassen
node bcs-adapter.mjs set-password           # fragt das BCS-Passwort ab (Schlüsselbund)
node bcs-adapter.mjs fetch --date 2026-10-26   # Login und Lesen testen, ändert nichts
```

**Task-IDs finden:** In der BCS-Tageserfassung hat jede Task-Zeile ein Attribut
`data-listtaskgroupoid="1234567890123_JTask"` (Rechtsklick › Untersuchen). Die Ziffern davor
sind die `taskId`. Das `mapping` ordnet per regulärem Ausdruck auf `ticket`, `description`
oder `project` zu; die erste passende Regel gewinnt.

## In Schichta einbinden

Einstellungen › Integrationen & Hooks › Lokaler Shell-Befehl (absoluter Node-Pfad, da Apps
nicht deinen Shell-PATH erben):

```
/opt/homebrew/bin/node ~/dev/personal/zeitbuch/adapters/bcs/bcs-adapter.mjs book --dry-run
```

Erst mit `--dry-run` testen („Hook jetzt testen“), dann `--dry-run` entfernen. Mit
„Hook automatisch ausführen…“ wird beim Markieren als gebucht direkt gebucht. Die Ausgabe
erscheint unter „Letzte Hook-Ausgabe“.

## Befehle

| Befehl | Wirkung |
| --- | --- |
| `plan` | Payload + Zuordnung prüfen, ohne BCS |
| `book [--dry-run] [--replace]` | buchen |
| `fetch --date YYYY-MM-DD` | vorhandene Einträge anzeigen |
| `set-password` | Passwort im Schlüsselbund speichern |

Exit-Codes: `0` ok · `1` Fehler · `2` bewusst abgelehnt (Plan-Probleme oder Tag schon belegt).
Bei Fehlern im Browser liegt ein Screenshot unter `$TMPDIR/schichta-bcs-fehler-*.png`.

## Tests

```bash
npm test
```

Die Ende-zu-Ende-Tests steuern Chrome gegen einen nachgebauten BCS (`test/fake-bcs.mjs`).
Sie prüfen den Ablauf des Adapters, **nicht** ob deine BCS-Version dieselbe Seitenstruktur hat –
dafür `fetch` und `book --dry-run` gegen dein echtes BCS.
