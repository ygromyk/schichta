SCHICHTA – LOKALE STUNDENNOTIZEN

Start ohne Installation: index.html im Browser öffnen.
Für automatische Git-Logs: SCHICHTA_REPOS=~/Projekte/repo-a:~/Projekte/repo-b python3 server.py
Dann http://127.0.0.1:8765 öffnen. Diesen Port und Browser für dieselben Daten beibehalten.

macOS-Desktop-App: `Schichta.app` bietet einen praktischen 30-Minuten-Statusbar-Check-in
(`z.` oben in der Menüleiste, Tastenkombination `⌘K`, Speichern als Tagesnotiz mit Zeitstempel
oder direkt als geschätzter 30-Minuten-Eintrag).

Datum auswählen, Ticket (optional), Dauer und Beschreibung eintragen.
Dauer: 1:30 = 1 Stunde 30 Minuten; 1,5 oder 1.5 = 1,5 Stunden.
Geschätzte Zeiten markieren und vor der Buchung bearbeiten/bestätigen.
Einträge werden mit „Eintrag speichern“ gespeichert. Tagesnotizen, Logtexte und
eingefügte KI-Antworten werden beim Tippen lokal gespeichert.
Die Daten liegen im localStorage dieses Browsers und dieser Adresse.
Dateiöffnung und localhost haben getrennte Speicher. Zum Wechsel zuerst eine
JSON-Sicherung exportieren und am neuen Ort importieren. Keine Cloud-Synchronisation.
Browserdaten-Löschen kann die Daten entfernen: regelmäßig Sicherung exportieren.
Import ersetzt nach Bestätigung den gesamten Datenbestand.

Tagesabschluss: Entwurf kopieren oder als TXT herunterladen.
Die Vorlage entspricht den Eingabefeldern der projektron-bcs-cli:
Datum DD.MM.YYYY, Gesamtzeit HH:MM, je Eintrag Beschreibung, Ticket, Zeit HH:MM.
Dies ist KEIN CLI-Dateiimport und KEINE direkte BCS-Buchung.
CLI-Quellcode geprüft: main / 8fd277ec6427b366557f476177b85e1472c2d643.
https://github.com/pgebert/projektron-bcs-cli/blob/main/src/commands/addCommand.ts
Die CLI setzt beim Speichern den Tag zurück; BCS-Projektmapping und bestehende
Buchungen müssen vor einer echten Übertragung geprüft werden.
FREITEXT UND CHATGPT
1. Tagesnotizen frei schreiben, inklusive tatsächlicher/ungefährer Zeiten.
2. „Git-Logs für diesen Tag laden“: Der lokale Python-Server liest eigene Commits
   und HEAD-Reflogs der in SCHICHTA_REPOS (durch „:“ getrennt) angegebenen Repositories.
   Keine Quelldateien, Passwörter, Chatdaten oder Remote-Abfragen. Autorfilter:
   SCHICHTA_AUTHOR oder `git config user.name`. Datum nach Europe/Berlin, inklusive Sommer-/Winterzeit.
3. „Analyseauftrag für diesen Chat vorbereiten“, Inhalt prüfen und kopieren.
4. Im Codex-/ChatGPT-Chat einfügen und auswerten lassen.
5. Die JSON-Antwort unter „ChatGPT-Antwort übernehmen“ einfügen. Vorschläge
   anzeigen, Zeiten ergänzen/korrigieren und einzeln übernehmen.
   Offene Zeiten werden nicht erfunden. Vorschläge bleiben als Schätzung markiert.
   Vorhandene Buchungen bleiben erhalten; erneute Übernahme derselben Tätigkeit
   wird verhindert. Alle Texte werden als Text und nicht als HTML dargestellt.

Die App ruft keine KI-API auf. Erst dein Einfügen im Chat gibt den Kontext an
ChatGPT weiter. Die bestehende Chat-Automation ist nicht automatisch angebunden.
Notizen sind pro Tag gespeichert und Teil der JSON-Sicherung. Alte Sicherungen
ohne Tagesnotizen bleiben kompatibel. Reine Dateiöffnung unterstützt keine Git-Abfrage.

Tests: node --test core.test.cjs
Server-Tests: python3 -m unittest server_test.py
Keine externen Abhängigkeiten, Fonts oder Tracker. Nur lokale Abfragen an
127.0.0.1:8765; Git-Lesezugriff nur auf die in SCHICHTA_REPOS angegebenen Repositories.

BUCHUNGSZIELE (TARGET-DATEIEN)
Andere Systeme werden ohne App-Änderung über JSON-Dateien angebunden:
~/Library/Application Support/Schichta/targets/<name>.json
Vorlage: targets/clockify.example.json (wird beim ersten Öffnen in den Ordner kopiert;
*.example.json wird nie geladen). Felder: name, method (POST/PUT/PATCH), url,
mode (perEntry = eine Anfrage pro Eintrag, perDay = eine pro Tag), auth, headers, body, map.
auth.type: none | bearer | basic (+username) | header (+header). In der Datei steht nur der
Name des Secrets; den Wert unter Einstellungen > Integrationen im Schlüsselbund speichern.
Platzhalter {{...}}: date, dateFormatted, author, totalMinutes, totalHours, totalDuration,
entries; pro Eintrag entry.ticket, entry.description, entry.minutes, entry.hours,
entry.duration, entry.estimated, entry.project, entry.start/entry.end (UTC),
entry.startTime/entry.endTime (HH:mm). Start/Ende werden ab Arbeitsbeginn lückenlos
hintereinander gelegt. {{map.ticket}} übersetzt das Ticket über die map-Tabelle.
Ist ein Wert nur ein Platzhalter, bleibt der Typ erhalten (Zahl, Bool, Liste).
Nur https (http nur für localhost), keine Weiterleitungen. Senden erst nach Vorschau;
die Vorschau zeigt Auth-Header maskiert. Für Systeme mit Login-Session (z. B. BCS)
weiterhin den Shell-Hook nutzen.

BCS-ADAPTER
adapters/bcs/ ist ein eigenständiges Node-Programm, das einen Tag in Projektron BCS bucht
(Browser-Automatisierung, Passwort im Schlüsselbund). Einbindung als Shell-Hook, Details
in adapters/bcs/README.md. Shell-Hooks dürfen jetzt bis zu 180 s laufen.

KI-ZUSAMMENFASSUNG
Button „KI“ im Hauptfenster: liest Tagesnotizen, Git-Aktivität und Claude-Code-/Codex-Chats
des Tages (~/.claude/projects, ~/.codex/sessions; nur Sitzungen in getrackten Repositories,
offensichtliche Geheimnisse entfernt), zeigt den vollständigen Auftrag als Vorschau und schickt
ihn erst nach Klick per stdin an den eingestellten Befehl. Die JSON-Antwort wird zu
Vorschlägen (als Schätzung markiert, Zeit offen = 0, muss vor Übernahme ergänzt werden)
plus Zusammenfassung und Rückfragen. Die App ruft keine KI-API direkt auf.
Werkzeuge (Einstellungen > Integrationen): Claude Code (ohne Tools/MCP/Hooks), Codex
(read-only), Ollama (lokal, llama3.1) oder eigene Dateien in
~/Library/Application Support/Schichta/ai-tools/<name>.json: {"name": "...", "command": "..."}.
