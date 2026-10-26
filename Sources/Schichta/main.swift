import Cocoa
import SwiftUI

// MARK: - Entry Point & Self-Tests

// Ein Hook- oder KI-Befehl, der vor dem Lesen von stdin endet, soll einen Schreibfehler liefern, nicht die App beenden.
signal(SIGPIPE, SIG_IGN)

if CommandLine.arguments.contains("--generate-icon") {
    let targetPath: String
    if let idx = CommandLine.arguments.firstIndex(of: "--generate-icon"), idx + 1 < CommandLine.arguments.count {
        targetPath = CommandLine.arguments[idx + 1]
    } else {
        targetPath = "AppIcon.iconset"
    }
    let targetURL = URL(fileURLWithPath: targetPath)
    do {
        try AppIconGenerator.generateIconSet(to: targetURL)
        print("Icon-Set generiert unter: \(targetURL.path)")
        exit(0)
    } catch {
        fputs("Fehler beim Erzeugen des Icon-Sets: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else if CommandLine.arguments.contains("--self-test") {
    print("Starte Schichta Desktop-Selbsttest...")

    // 1. Activity bounds & git check
    let bounds = try Activity.bounds("2026-10-25")
    precondition(bounds.0 == "2026-10-25T00:00:00+02:00", "Start bounds mismatch")
    precondition(bounds.1 == "2026-10-25T23:59:59+01:00", "End bounds mismatch")
    do {
        _ = try Activity.bounds("2026-02-30")
        fatalError("Ungültiges Datum wurde fälschlicherweise akzeptiert")
    } catch {}

    // Keine fest hinterlegten Repositories: ohne Konfiguration wird nichts gelesen.
    let result = try Activity.readRepos("2026-10-12", repos: [], authorFilter: nil)
    let repos = result["repositories"] as! [[String: Any]]
    precondition(repos.isEmpty, "Ohne Konfiguration dürfen keine Repositories gelesen werden")

    // 2. SchichtaCore Parser & Formatter tests
    precondition((try? SchichtaCore.parseMinutes("1:30")) == 90)
    precondition((try? SchichtaCore.parseMinutes("01:05")) == 65)
    precondition((try? SchichtaCore.parseMinutes("1,5")) == 90)
    precondition((try? SchichtaCore.parseMinutes("1.25")) == 75)
    precondition((try? SchichtaCore.parseMinutes("30m")) == 30)
    precondition((try? SchichtaCore.parseMinutes("45 min")) == 45)
    precondition((try? SchichtaCore.parseMinutes("2h")) == 120)
    precondition((try? SchichtaCore.parseMinutes("1,5h")) == 90)

    for bad in ["1:60", "-2", "0", "1:2", "abc", "24:01", "1,5abc"] {
        var threw = false
        do { _ = try SchichtaCore.parseMinutes(bad) } catch { threw = true }
        precondition(threw, "parseMinutes sollte bei '\(bad)' einen Fehler werfen")
    }

    precondition(SchichtaCore.formatTime(90) == "01:30")
    precondition(SchichtaCore.formatTime(65) == "01:05")
    precondition(SchichtaCore.formatGermanDate("2026-10-26") == "26.10.2026")

    // CheckIn String tests
    let checkIn1 = try SchichtaCore.appendCheckIn(existingNotes: "", timeStr: "12:30", text: "Replay getestet")
    precondition(checkIn1 == "- 12:30 (30 Min.): Replay getestet", "CheckIn Formatierung fehlerhaft: \(checkIn1)")

    let checkIn2 = try SchichtaCore.appendCheckIn(existingNotes: checkIn1, timeStr: "13:00", text: "Abstimmung mit dem Team", ticket: "proj-2800")
    precondition(checkIn2 == "- 12:30 (30 Min.): Replay getestet\n- 13:00 (30 Min.): [PROJ-2800] Abstimmung mit dem Team", "CheckIn Append fehlerhaft: \(checkIn2)")

    let checkInCustom = try SchichtaCore.appendCheckIn(existingNotes: "", timeStr: "14:00", text: "Sprint Planning", ticket: "proj-2900", minutes: 45)
    precondition(checkInCustom == "- 14:00 (45 Min.): [PROJ-2900] Sprint Planning", "CheckIn mit benutzerdefinierten Minuten fehlerhaft: \(checkInCustom)")

    let testDate = Date()
    let window15 = AppDelegate.checkInWindowString(for: testDate, intervalMinutes: 15)
    precondition(window15.contains("· 15 Min. Check-in"), "checkInWindowString fehlerhaft für 15m")
    let window60 = AppDelegate.checkInWindowString(for: testDate, intervalMinutes: 60)
    precondition(window60.contains("· 60 Min. Check-in"), "checkInWindowString fehlerhaft für 60m")

    do {
        _ = try SchichtaCore.appendCheckIn(existingNotes: "", timeStr: "12:30", text: "   ")
        fatalError("Leere Check-In Notiz sollte Fehler werfen")
    } catch {}

    // BCS Report test
    let testEntries = [
        Entry(id: "1", date: "2026-10-26", ticket: "PROJ-2800", description: "Replay prüfen", minutes: 90, estimated: true),
        Entry(id: "2", date: "2026-10-26", ticket: "", description: "Abstimmung", minutes: 15, estimated: false)
    ]
    let report = SchichtaCore.bcsReport(day: "2026-10-26", entries: testEntries)
    precondition(report.contains("Datum: 26.10.2026"))
    precondition(report.contains("Gesamtzeit: 01:45"))
    precondition(report.contains("1. Replay prüfen"))
    precondition(report.contains("Ticket: PROJ-2800"))
    precondition(report.contains("Dauer: 01:30 (Schätzung – prüfen)"))
    precondition(report.contains("Ticket: Ohne Ticket"))

    // Database Validation test
    let validDB = Database(version: 1, entries: testEntries, journal: ["2026-10-26": JournalItem(notes: "Notiz", logs: "Log", answer: "")])
    _ = try SchichtaCore.validate(database: validDB)

    // 3. AutoSynthesizer test
    let sampleJournal = JournalItem(
        notes: "- 09:30 (30 Min.): [PROJ-2800] Replay testen\n- 10:00 (30 Min.): [PROJ-2800] Replay testen\n- 11:30 (30 Min.): [PROJ-2900] Architektur\nTeam-Meeting 45m",
        logs: "",
        answer: ""
    )
    let sampleGitResult: [String: Any] = [
        "repositories": [
            [
                "repository": "example-app",
                "commits": [
                    "text": "abc1234 | Autorzeit: 2026-10-26T10:00:00+02:00 | Commitzeit: 2026-10-26T10:00:00+02:00 | feat: PROJ-3000 Fix timing in order controller\ndef5678 | Autorzeit: 2026-10-26T11:00:00+02:00 | Commitzeit: 2026-10-26T11:00:00+02:00 | fix: PROJ-3000 Add order unit tests"
                ]
            ]
        ]
    ]

    let synthProposals = AutoSynthesizer.synthesizeDay(
        day: "2026-10-26",
        journal: sampleJournal,
        gitResult: sampleGitResult,
        existingEntries: []
    )

    print("Synthetisierte Vorschläge: \(synthProposals.count)")
    for p in synthProposals {
        print("  -> [\(p.source)] Ticket: '\(p.ticket)' | \(p.description) (\(p.minutes) Min)")
    }

    // Check grouped check-ins: PROJ-2800 should be grouped to 60 minutes
    guard let replayProp = synthProposals.first(where: { $0.ticket == "PROJ-2800" }) else {
        fatalError("PROJ-2800 wurde nicht synthetisiert")
    }
    precondition(replayProp.minutes == 60, "Zwei 30m Check-ins sollten zu 60 Minuten addiert werden (ist: \(replayProp.minutes))")
    precondition(replayProp.source == "Aus 30m Check-ins")

    // Check freeform note parsing: "Team-Meeting 45m"
    guard let meetingProp = synthProposals.first(where: { $0.description.contains("Team-Meeting") }) else {
        fatalError("Team-Meeting wurde nicht aus freien Notizen erkannt")
    }
    precondition(meetingProp.minutes == 45, "Meeting sollte 45 Min haben")
    precondition(meetingProp.source == "Aus Tagesnotiz")

    // Check Git commits grouping: PROJ-3000 should combine both commit subjects
    guard let gitProp = synthProposals.first(where: { $0.ticket == "PROJ-3000" }) else {
        fatalError("Git-Commits wurden nicht synthetisiert")
    }
    precondition(gitProp.description.contains("example-app: Fix timing in order controller, Add order unit tests"))
    precondition(gitProp.source == "Git · example-app")

    // Check existing entry filtering
    let synthFiltered = AutoSynthesizer.synthesizeDay(
        day: "2026-10-26",
        journal: sampleJournal,
        gitResult: sampleGitResult,
        existingEntries: [
            Entry(id: "ex1", date: "2026-10-26", ticket: "PROJ-2800", description: "Replay testen", minutes: 60, estimated: false)
        ]
    )
    precondition(!synthFiltered.contains(where: { $0.ticket == "PROJ-2800" }), "Bereits erfasste Einträge dürfen nicht erneut vorgeschlagen werden")

    // 4. Icon generation self-test
    let icon = AppIconGenerator.makeIcon(size: 128)
    precondition(icon.size.width == 128 && icon.size.height == 128, "AppIconGenerator erzeugt falsche Größe")

    // 5. Booking Status & JournalItem backward compatibility test
    let jsonWithoutBooked = """
    {"notes":"Tagesnotiz","logs":"","answer":""}
    """.data(using: .utf8)!
    let decodedOld = try JSONDecoder().decode(JournalItem.self, from: jsonWithoutBooked)
    precondition(decodedOld.booked == false, "Alte JournalItems ohne 'booked' Feld sollten mit booked == false dekodiert werden")

    let jsonWithBooked = """
    {"notes":"Tagesnotiz","logs":"","answer":"","booked":true}
    """.data(using: .utf8)!
    let decodedNew = try JSONDecoder().decode(JournalItem.self, from: jsonWithBooked)
    precondition(decodedNew.booked == true, "JournalItem mit 'booked': true sollte korrekt dekodiert werden")

    let testDB = Database(version: 1, entries: [
        Entry(id: "e1", date: "2026-10-23", ticket: "PROJ-1", description: "Test", minutes: 30, estimated: false)
    ], journal: [
        "2026-10-23": JournalItem(notes: "Notiz", logs: "", answer: "", booked: true)
    ])
    let validatedDB = try SchichtaCore.validate(database: testDB)
    precondition(validatedDB.journal["2026-10-23"]?.booked == true, "validate(database:) muss 'booked' Feld beibehalten")
    print("5. Passed")

    // 6. Day booking queries & previousWorkingDay tests
    // Eigene Datei und eigene UserDefaults-Domain: Der Test darf weder echte Einträge überschreiben
    // noch Einstellungen ändern oder einen eingerichteten Hook auslösen.
    // Feste Domain, vor dem Test geleert: jeder Lauf startet mit Standardwerten, es sammeln sich keine Dateien an.
    let testDefaultsSuite = "local.schichta.selftest"
    UserDefaults.standard.removePersistentDomain(forName: testDefaultsSuite)
    let testStoreURL = FileManager.default.temporaryDirectory.appendingPathComponent("schichta-selftest-\(UUID().uuidString)/schichta.json")
    let mockStore = SchichtaStore(storeURL: testStoreURL, defaults: UserDefaults(suiteName: testDefaultsSuite)!)
    print("Store created")
    mockStore.database = Database(version: 1, entries: [
        Entry(id: "e_fri", date: "2026-10-23", ticket: "PROJ-2800", description: "Freitag Arbeit", minutes: 60, estimated: false)
    ], journal: [
        "2026-10-23": JournalItem(notes: "Freitagsnotiz", logs: "", answer: "", booked: false),
        "2026-10-22": JournalItem(notes: "Donnerstag", logs: "", answer: "", booked: true)
    ])

    precondition(mockStore.isDayUnbooked("2026-10-23") == true, "Freitag sollte als ungebucht gelten")
    precondition(mockStore.isDayUnbooked("2026-10-22") == false, "Donnerstag (booked == true) darf nicht als ungebucht gelten")

    let prevDayBeforeMon = mockStore.previousWorkingDay(before: "2026-10-26")
    precondition(prevDayBeforeMon == "2026-10-23", "Vor Montag muss der letzte ungebuchte Arbeitstag Freitag sein (ist: \(prevDayBeforeMon))")

    mockStore.markDayBooked("2026-10-23", booked: true)
    precondition(mockStore.database.journal["2026-10-23"]?.booked == true, "markDayBooked muss booked auf true setzen")
    precondition(mockStore.isDayUnbooked("2026-10-23") == false, "Nach dem Buchen darf Freitag nicht mehr ungebucht sein")

    precondition(mockStore.reminderIntervalMinutes >= 5, "Standard-Intervall muss mindestens 5 sein")

    // 7. Working Days & Work Hours Management tests
    mockStore.workingDays = [2, 3, 4, 5, 6] // Mo - Fr
    mockStore.workStartHour = 9
    mockStore.workStartMinute = 0
    mockStore.workEndHour = 17
    mockStore.workEndMinute = 0
    mockStore.onlyPromptDuringWorkHours = true
    mockStore.dailyTargetMinutes = 480

    precondition(mockStore.isWorkingDay("2026-10-26") == true, "Montag 2026-10-26 muss ein Arbeitstag sein")
    precondition(mockStore.isWorkingDay("2026-10-23") == true, "Freitag 2026-10-23 muss ein Arbeitstag sein")
    precondition(mockStore.isWorkingDay("2026-10-24") == false, "Samstag 2026-10-24 darf kein Arbeitstag sein")
    precondition(mockStore.isWorkingDay("2026-10-25") == false, "Sonntag 2026-10-25 darf kein Arbeitstag sein")

    // Custom working day test: Saturday only
    mockStore.workingDays = [7]
    precondition(mockStore.isWorkingDay("2026-10-24") == true, "Samstag muss bei Custom-WorkingDays aktiv sein")
    precondition(mockStore.isWorkingDay("2026-10-26") == false, "Montag darf bei Saturday-only kein Arbeitstag sein")
    mockStore.workingDays = [2, 3, 4, 5, 6]

    // unbookedPreviousDay skipping weekends
    mockStore.database = Database(version: 1, entries: [], journal: [
        "2026-10-25": JournalItem(notes: "Sonntagsnotiz", logs: "", answer: "", booked: false),
        "2026-10-24": JournalItem(notes: "Samstagsnotiz", logs: "", answer: "", booked: false),
        "2026-10-23": JournalItem(notes: "Freitagsarbeit", logs: "", answer: "", booked: false),
        "2026-10-22": JournalItem(notes: "Donnerstag", logs: "", answer: "", booked: true)
    ])
    let unbookedBeforeMon = mockStore.unbookedPreviousDay(today: "2026-10-26")
    precondition(unbookedBeforeMon == "2026-10-23", "unbookedPreviousDay muss Wochenende überspringen und Freitag liefern (ist: \(String(describing: unbookedBeforeMon)))")

    // Working hours simulation
    let testBerlinCal = Berlin.calendar

    var mondayComps = DateComponents()
    mondayComps.year = 2026; mondayComps.month = 10; mondayComps.day = 26
    mondayComps.hour = 10; mondayComps.minute = 30 // Mo 10:30 (during work hours)
    let mondayDuring = testBerlinCal.date(from: mondayComps)!
    precondition(mockStore.isCurrentlyWithinWorkingHours(mondayDuring) == true, "Mo 10:30 muss innerhalb der Arbeitszeit liegen")

    mondayComps.hour = 8; mondayComps.minute = 30 // Mo 08:30 (before work hours)
    let mondayBefore = testBerlinCal.date(from: mondayComps)!
    precondition(mockStore.isCurrentlyWithinWorkingHours(mondayBefore) == false, "Mo 08:30 muss außerhalb der Arbeitszeit liegen")

    mondayComps.hour = 17; mondayComps.minute = 30 // Mo 17:30 (after work hours)
    let mondayAfter = testBerlinCal.date(from: mondayComps)!
    precondition(mockStore.isCurrentlyWithinWorkingHours(mondayAfter) == false, "Mo 17:30 muss außerhalb der Arbeitszeit liegen")

    var sundayComps = DateComponents()
    sundayComps.year = 2026; sundayComps.month = 10; sundayComps.day = 25
    sundayComps.hour = 14; sundayComps.minute = 0 // So 14:00 (weekend)
    let sundayMidday = testBerlinCal.date(from: sundayComps)!
    precondition(mockStore.isCurrentlyWithinWorkingHours(sundayMidday) == false, "Sonntag darf nicht innerhalb der Arbeitszeit liegen")

    // 8. Bilingual switching & Localization tests
    mockStore.appLanguage = .de
    precondition(mockStore.t("Heute", "Today") == "Heute")
    precondition(SchichtaCore.formatFullDate("2026-10-26", language: .de).contains("Montag"))
    precondition(AppDelegate.checkInWindowString(for: mondayDuring, intervalMinutes: 15, language: .de).contains("· 15 Min. Check-in"))
    precondition(CheckInMode.both.title(for: .de) == "Als Eintrag + Notiz")
    precondition(CheckInMode.noteOnly.title(for: .de) == "Nur als Notiz")

    mockStore.appLanguage = .en
    precondition(mockStore.t("Heute", "Today") == "Today")
    precondition(SchichtaCore.formatFullDate("2026-10-26", language: .en).contains("Monday"))
    precondition(AppDelegate.checkInWindowString(for: mondayDuring, intervalMinutes: 15, language: .en).contains("· 15 min check-in"))
    precondition(CheckInMode.both.title(for: .en) == "As entry + note")
    precondition(CheckInMode.noteOnly.title(for: .en) == "Note only")

    // Reset language to German
    mockStore.appLanguage = .de

    // 9. View instantiation smoke test
    _ = SettingsView(store: mockStore)

    // 10. TrackedRepo, Activity.readRepos & AutoSynthesizer with project name & default ticket
    print("Starting check 10...")
    let testRepo1 = TrackedRepo(path: "/Users/me/Projects/example-app", projectName: "Example App", defaultTicket: "PROJ-2800", enabled: true)
    precondition(testRepo1.folderName == "example-app", "folderName mismatch")
    precondition(testRepo1.displayLabel == "Example App", "displayLabel mismatch")
    let testRepoFallback = TrackedRepo(path: "/Users/me/Projects/example-api", projectName: "", defaultTicket: "", enabled: true)
    precondition(testRepoFallback.displayLabel == "example-api", "displayLabel fallback mismatch")
    print("TrackedRepo labels ok")

    let encodedRepos = try JSONEncoder().encode([testRepo1, testRepoFallback])
    let decodedRepos = try JSONDecoder().decode([TrackedRepo].self, from: encodedRepos)
    precondition(decodedRepos.count == 2 && decodedRepos[0].projectName == "Example App", "TrackedRepo Codable failed")
    print("TrackedRepo JSON ok")

    // Activity.readRepos
    let readReposResult = try Activity.readRepos("2026-10-12", repos: [testRepo1, testRepoFallback], authorFilter: "Max Mustermann")
    let reposData = readReposResult["repositories"] as! [[String: Any]]
    precondition(reposData.count == 2, "readRepos sollte 2 Repositories liefern")
    precondition(reposData[0]["projectName"] as? String == "Example App")
    precondition(reposData[0]["defaultTicket"] as? String == "PROJ-2800")
    print("readRepos ok")

    // AutoSynthesizer with repo displayLabel & defaultTicket
    let gitResultWithRepoMeta: [String: Any] = [
        "repositories": [
            [
                "repository": "example-app",
                "projectName": "Example App",
                "defaultTicket": "PROJ-2800",
                "commits": [
                    "text": "c1a2b3c | Autorzeit: 2026-10-26T14:00:00+02:00 | Commitzeit: 2026-10-26T14:00:00+02:00 | Refactor connection handler"
                ]
            ],
            [
                "repository": "example-api",
                "projectName": "Example API",
                "defaultTicket": "PROJ-1000",
                "commits": ["text": ""],
                "head_activity": ["text": "reflog 1 | commit: checkout branch PROJ-5555"],
                "working_tree": [
                    "text": " M src/index.ts\n M src/controller.ts\n"
                ]
            ]
        ]
    ]

    let repoSynthProposals = AutoSynthesizer.synthesizeDay(
        day: "2026-10-26",
        journal: JournalItem(),
        gitResult: gitResultWithRepoMeta,
        existingEntries: []
    )
    print("Synthesized \(repoSynthProposals.count) proposals for check 10:")
    for p in repoSynthProposals {
        print("  -> [\(p.source)] ticket='\(p.ticket)' desc='\(p.description)' proj='\(p.project)'")
    }

    guard let defaultTicketProp = repoSynthProposals.first(where: { $0.ticket == "PROJ-2800" }) else {
        fatalError("Vorschlag mit Default-Ticket PROJ-2800 wurde nicht erzeugt")
    }
    precondition(defaultTicketProp.description.hasPrefix("Example App:"), "Beschreibung sollte Projektnamen als Präfix haben: \(defaultTicketProp.description)")
    precondition(defaultTicketProp.project == "Example App", "Projekt sollte 'Example App' sein")
    print("Default ticket proposal ok")

    // Working tree proposal for example-api
    guard let wtProp = repoSynthProposals.first(where: { $0.description.contains("Lokale Änderungen") }) else {
        fatalError("Working-Tree Vorschlag für example-api wurde nicht erzeugt")
    }
    precondition(wtProp.description.contains("Example API: Lokale Änderungen (2 Dateien in Arbeit)"), "Working-tree Beschreibung fehlerhaft: \(wtProp.description)")
    precondition(wtProp.minutes == 30, "Working-tree Dauer sollte 30 Min sein")
    precondition(wtProp.ticket == "PROJ-5555", "Working-tree Ticket sollte aus HEAD-Activity bezogen werden: \(wtProp.ticket)")
    print("Working-tree proposal ok")

    // 11. External Hooks & JSON-Payload generation with project assignment
    let hookTestEntries = [
        Entry(id: "h1", date: "2026-10-26", ticket: "PROJ-2800", description: "Example App: Replay prüfen", minutes: 60, estimated: false),
        Entry(id: "h2", date: "2026-10-26", ticket: "PROJ-9999", description: "Example API: CI fix", minutes: 30, estimated: true),
        Entry(id: "h3", date: "2026-10-26", ticket: "", description: "Team Meeting", minutes: 30, estimated: false, project: "Custom Org")
    ]
    let hookPayload = SchichtaCore.buildHookPayload(
        day: "2026-10-26",
        entries: hookTestEntries,
        repos: [testRepo1, testRepoFallback],
        author: "Max Mustermann"
    )
    precondition(hookPayload["event"] as? String == "day_booked", "Hook event mismatch")
    precondition(hookPayload["date"] as? String == "2026-10-26", "Hook date mismatch")
    precondition(hookPayload["totalMinutes"] as? Int == 120, "Hook totalMinutes mismatch")
    precondition(hookPayload["totalFormatted"] as? String == "02:00", "Hook totalFormatted mismatch")

    let hookEntries = hookPayload["entries"] as! [[String: Any]]
    precondition(hookEntries.count == 3, "Hook entries count mismatch")
    print("hookEntry 0 project: \(hookEntries[0]["projectName"] ?? "")")
    print("hookEntry 1 project: \(hookEntries[1]["projectName"] ?? "")")
    print("hookEntry 2 project: \(hookEntries[2]["projectName"] ?? "")")
    precondition(hookEntries[0]["projectName"] as? String == "Example App", "Eintrag mit Default-Ticket Match sollte 'Example App' zugeordnet werden")
    precondition(hookEntries[1]["projectName"] as? String == "example-api", "Eintrag mit Repo-Präfix sollte 'example-api' zugeordnet werden")
    precondition(hookEntries[2]["projectName"] as? String == "Custom Org", "Eintrag mit explizitem project sollte 'Custom Org' behalten")
    print("Hook payload ok")

    // 12. Entry Backward compatibility test
    let oldEntryJSON = """
    {"id":"old-entry-1","date":"2026-10-26","ticket":"PROJ-10","description":"Old JSON without project","minutes":45,"estimated":false}
    """.data(using: .utf8)!
    let decodedOldEntry = try JSONDecoder().decode(Entry.self, from: oldEntryJSON)
    precondition(decodedOldEntry.project == "", "project sollte bei altem JSON leer initialisiert werden")

    // 13. Shell Hook execution environment check
    var testEnv = ProcessInfo.processInfo.environment
    testEnv["SCHICHTA_TOTAL_HHMM"] = "02:00"
    let shellOut = try Shell.run("/bin/zsh", ["-c", "echo $SCHICHTA_TOTAL_HHMM"], environment: testEnv, timeout: 10).text
        .trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(shellOut == "02:00", "Shell environment check failed: \(shellOut)")

    // Befehl, der stdin nie liest: großes stdin darf weder hängen noch die App per SIGPIPE beenden.
    let bigInput = Data(repeating: UInt8(ascii: "x"), count: 1_000_000)
    let ignoresStdin = try Shell.run("/bin/zsh", ["-c", "echo ok"], stdin: bigInput, timeout: 10)
    precondition(ignoresStdin.status == 0 && ignoresStdin.text == "ok\n", "Shell.run mit ungelesenem stdin fehlerhaft")
    let echoed = try Shell.run("/bin/cat", [], stdin: bigInput, timeout: 10)
    precondition(echoed.stdout == bigInput, "Shell.run muss großes stdin vollständig übergeben")
    print("Shell.run ok")

    // 14. Multi-screen activeScreen() test
    let activeSc = AppDelegate.activeScreen()
    precondition(activeSc.frame.width > 0 && activeSc.frame.height > 0, "activeScreen() muss einen gültigen Monitor mit Breite > 0 liefern")
    print("Multi-Screen activeScreen() ok: \(activeSc.frame)")

    // 15. Check-in Sound settings test
    precondition(mockStore.checkInSoundEnabled == true, "checkInSoundEnabled sollte standardmäßig true sein")
    precondition(mockStore.checkInSoundName == "Glass", "checkInSoundName sollte standardmäßig Glass sein")
    precondition(SchichtaStore.availableSounds.contains("Hero"), "availableSounds sollte Hero enthalten")
    mockStore.checkInSoundName = "Hero"
    precondition(mockStore.checkInSoundName == "Hero", "checkInSoundName konnte nicht geändert werden")
    mockStore.checkInSoundName = "Glass"
    print("Check-in Sound settings ok")

    // 16. Notification Content & Schichta App-Icon attachment test
    let notifContent = AppDelegate.makeNotificationContent(
        title: "Schichta Test",
        subtitle: "Check-in",
        body: "Was machst du gerade?",
        soundEnabled: true
    )
    precondition(notifContent.title == "Schichta Test", "Notification title mismatch")
    precondition(notifContent.subtitle == "Check-in", "Notification subtitle mismatch")
    precondition(notifContent.body == "Was machst du gerade?", "Notification body mismatch")
    precondition(notifContent.sound != nil, "Notification sound sollte aktiviert sein")
    precondition(notifContent.attachments.count == 1, "makeNotificationContent muss genau 1 Attachment (Schichta-Icon) enthalten (ist: \(notifContent.attachments.count))")
    precondition(notifContent.attachments[0].identifier == "schichta-icon", "Notification attachment identifier mismatch")
    let persistentIconPath = AppDelegate.notificationIconURL.path
    precondition(FileManager.default.fileExists(atPath: persistentIconPath), "Notification icon PNG wurde nicht in Application Support gespeichert")
    print("Notification Content & App-Icon attachment ok")

    // 17. Booking Targets: Rendering, Typen, Auth, Maskierung, Fehlerfälle
    let targetJSON = """
    {"name":"Test","url":"https://example.test/api/{{entry.ticket}}/x","mode":"perEntry",
     "auth":{"type":"bearer","secret":"t1"},
     "headers":{"X-Day":"{{date}}"},
     "body":{"minutes":"{{entry.minutes}}","hours":"{{entry.hours}}","text":"{{entry.ticket}} {{entry.description}}",
             "task":"{{map.ticket}}","start":"{{entry.start}}","end":"{{entry.end}}","est":"{{entry.estimated}}"},
     "map":{"PROJ-1":"task-9","PROJ-2":"task-8"}}
    """
    let testTarget = try BookingTarget.parse(id: "test", data: Data(targetJSON.utf8))
    let targetEntries = [
        Entry(id: "a", date: "2026-10-26", ticket: "PROJ-1", description: "Review", minutes: 90, estimated: false),
        Entry(id: "b", date: "2026-10-26", ticket: "PROJ-2", description: "Fix", minutes: 30, estimated: true)
    ]
    let testSecret: (String) -> String? = { $0 == "t1" ? "s3cr3t" : nil }
    let targetRequests = try TargetRenderer.prepare(target: testTarget, day: "2026-10-26", entries: targetEntries, author: "Max Mustermann",
                                                    workStart: (9, 0), repos: [], secret: testSecret)
    precondition(targetRequests.count == 2, "perEntry muss eine Anfrage pro Eintrag erzeugen")
    precondition(targetRequests[0].url.absoluteString == "https://example.test/api/PROJ-1/x")
    precondition(targetRequests[0].headers["Authorization"] == "Bearer s3cr3t")
    precondition(targetRequests[0].headers["X-Day"] == "2026-10-26")
    let body0 = try JSONSerialization.jsonObject(with: targetRequests[0].body) as! [String: Any]
    precondition(body0["minutes"] as? Int == 90, "Ganzer Platzhalter muss Zahl bleiben")
    precondition(body0["hours"] as? Double == 1.5)
    precondition(body0["text"] as? String == "PROJ-1 Review")
    precondition(body0["task"] as? String == "task-9")
    precondition(body0["start"] as? String == "2026-10-26T08:00:00Z", "09:00 Berlin (MEZ) = 08:00 UTC: \(body0["start"] ?? "")")
    precondition(body0["end"] as? String == "2026-10-26T09:30:00Z")
    precondition(body0["est"] as? Bool == false)
    let body1 = try JSONSerialization.jsonObject(with: targetRequests[1].body) as! [String: Any]
    precondition(body1["start"] as? String == "2026-10-26T09:30:00Z", "Einträge müssen lückenlos hintereinander liegen")
    precondition(!targetRequests[0].previewText.contains("s3cr3t") && targetRequests[0].previewText.contains("Authorization: ••••••"),
                 "Vorschau darf das Secret nicht zeigen")

    let dayTarget = try BookingTarget.parse(id: "day", data: Data("""
    {"url":"http://127.0.0.1:9/hook","mode":"perDay","body":{"entries":"{{entries}}","total":"{{totalMinutes}}","who":"{{author}}"}}
    """.utf8))
    let dayRequests = try TargetRenderer.prepare(target: dayTarget, day: "2026-10-26", entries: targetEntries, author: "Max Mustermann",
                                                 workStart: (9, 0), repos: [], secret: { _ in nil })
    precondition(dayRequests.count == 1, "perDay muss genau eine Anfrage erzeugen")
    let dayBody = try JSONSerialization.jsonObject(with: dayRequests[0].body) as! [String: Any]
    precondition((dayBody["entries"] as? [Any])?.count == 2 && dayBody["total"] as? Int == 120)

    func expectTargetFailure(_ message: String, _ block: () throws -> Void) {
        do { try block(); fatalError(message) } catch {}
    }
    expectTargetFailure("Fehlendes Secret muss scheitern") {
        _ = try TargetRenderer.prepare(target: testTarget, day: "2026-10-26", entries: targetEntries, author: "", workStart: (9, 0), repos: [], secret: { _ in nil })
    }
    expectTargetFailure("Unbekannter Platzhalter muss scheitern") {
        let t = try BookingTarget.parse(id: "x", data: Data(#"{"url":"https://a.test","body":{"x":"{{entry.nope}}"}}"#.utf8))
        _ = try TargetRenderer.prepare(target: t, day: "2026-10-26", entries: targetEntries, author: "", workStart: (9, 0), repos: [], secret: { _ in nil })
    }
    expectTargetFailure("Fehlende map-Zuordnung muss scheitern") {
        let t = try BookingTarget.parse(id: "x", data: Data(#"{"url":"https://a.test","body":{"x":"{{map.ticket}}"},"map":{"PROJ-1":"1"}}"#.utf8))
        _ = try TargetRenderer.prepare(target: t, day: "2026-10-26", entries: targetEntries, author: "", workStart: (9, 0), repos: [], secret: { _ in nil })
    }
    expectTargetFailure("http an fremden Host muss scheitern") {
        let t = try BookingTarget.parse(id: "x", data: Data(#"{"url":"http://a.test/x","body":{}}"#.utf8))
        _ = try TargetRenderer.prepare(target: t, day: "2026-10-26", entries: targetEntries, author: "", workStart: (9, 0), repos: [], secret: { _ in nil })
    }
    expectTargetFailure("Klartext-Secret in der Datei muss abgelehnt werden") {
        _ = try BookingTarget.parse(id: "x", data: Data(#"{"url":"https://a.test","auth":{"type":"bearer","secret":"n","token":"abc"}}"#.utf8))
    }
    if let example = Bundle.main.url(forResource: "clockify.example", withExtension: "json") {
        let parsed = try BookingTarget.parse(id: "clockify", data: Data(contentsOf: example))
        precondition(parsed.auth == .header(name: "X-Api-Key", secret: "clockify-api-key"), "Beispielziel fehlerhaft")
    }
    print("Booking Targets ok")

    // 18. KI-Zusammenfassung: Redaktion, Antwort-Parsing, Chat-Belege
    let redacted = SecretRedactor.redact("password=hunter2 und Bearer abc.def-123 und token: xyz sowie ghp_abcdefghijklmnopqrstuvwxyz12 bleibt PROJ-12")
    precondition(!redacted.contains("hunter2") && !redacted.contains("abc.def-123") && !redacted.contains("xyz") && !redacted.contains("ghp_"), "Redaktion unvollständig: \(redacted)")
    precondition(redacted.contains("PROJ-12") && redacted.contains("password=[ENTFERNT]"), "Redaktion zu aggressiv: \(redacted)")

    let aiAnswer = """
    Hier ist das Ergebnis:
    ```json
    {"summary":"Review und Fix.","entries":[{"ticket":"proj-1","description":"Review","minutes":90,"evidence":"Notiz"},
     {"ticket":"","description":"Abstimmung","minutes":null,"evidence":"Chat"},{"ticket":"","description":"  ","minutes":5}],
     "questions":["Wie lange Abstimmung?"]}
    ```
    """
    let aiResult = try AISummary.parse(aiAnswer)
    precondition(aiResult.summary == "Review und Fix.")
    precondition(aiResult.proposals.count == 2, "Leere Beschreibung muss verworfen werden")
    precondition(aiResult.proposals[0].ticket == "PROJ-1" && aiResult.proposals[0].minutes == 90 && aiResult.proposals[0].estimated)
    precondition(aiResult.proposals[1].minutes == 0 && aiResult.proposals[1].source.contains("Zeit offen"))
    precondition(aiResult.proposals.allSatisfy { $0.id.hasPrefix("ai-") })
    precondition(aiResult.questions == ["Wie lange Abstimmung?"])
    do { _ = try AISummary.parse("kein json"); fatalError("Antwort ohne JSON muss scheitern") } catch {}

    let fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("schichta-chat-test-\(UUID().uuidString)")
    let claudeDir = fakeHome.appendingPathComponent(".claude/projects/-work-app")
    let codexDir = fakeHome.appendingPathComponent(".codex/sessions/2026/10/26")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
    let claudeLines = [
        #"{"type":"user","timestamp":"2026-10-26T08:00:00.000Z","cwd":"/work/app/sub","gitBranch":"feature/x","message":{"role":"user","content":"Fix den Login-Bug token=geheim123"}}"#,
        #"{"type":"assistant","timestamp":"2026-10-26T08:05:00.000Z","cwd":"/work/app/sub","message":{"role":"assistant","content":[]}}"#,
        #"{"type":"user","timestamp":"2026-10-26T08:09:00.000Z","cwd":"/work/app/sub","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}"#,
        #"{"type":"user","timestamp":"2026-10-26T08:10:00.000Z","cwd":"/work/app/sub","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
        #"{"type":"user","timestamp":"2026-10-26T09:30:00.000Z","cwd":"/work/app/sub","message":{"role":"user","content":[{"type":"text","text":"Tests ergänzen"}]}}"#,
        #"{"type":"user","timestamp":"2026-10-25T09:30:00.000Z","cwd":"/work/app","message":{"role":"user","content":"Gestern"}}"#
    ]
    try claudeLines.joined(separator: "\n").write(to: claudeDir.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)
    try #"{"type":"user","timestamp":"2026-10-26T10:00:00Z","cwd":"/private/hobby","message":{"role":"user","content":"Privat"}}"#
        .write(to: claudeDir.appendingPathComponent("s2.jsonl"), atomically: true, encoding: .utf8)
    let codexLines = [
        #"{"timestamp":"2026-10-26T11:00:00.000Z","type":"session_meta","payload":{"cwd":"/work/app","git":{"branch":"main"}}}"#,
        #"{"timestamp":"2026-10-26T11:00:05.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}"#,
        #"{"timestamp":"2026-10-26T11:00:06.000Z","type":"event_msg","payload":{"type":"user_message","message":"Refactoring Service"}}"#,
        #"{"timestamp":"2026-10-26T11:04:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"ok"}}"#
    ]
    try codexLines.joined(separator: "\n").write(to: codexDir.appendingPathComponent("rollout-1.jsonl"), atomically: true, encoding: .utf8)
    let chatRepo = TrackedRepo(path: "/work/app", projectName: "App", defaultTicket: "", enabled: true)
    let chats = ChatActivity.read(day: "2026-10-26", repos: [chatRepo], home: fakeHome)
    try? FileManager.default.removeItem(at: fakeHome)
    precondition(chats.count == 2, "Erwartet 1 Claude- + 1 Codex-Sitzung, private Repos ausgeschlossen: \(chats.count)")
    let claudeChat = chats[0]
    precondition(claudeChat.tool == "Claude Code" && claudeChat.project == "App" && claudeChat.branch == "feature/x")
    precondition(claudeChat.prompts.count == 2 && claudeChat.prompts[1] == "Tests ergänzen", "Tool-Ergebnisse/Befehle dürfen keine Prompts sein: \(claudeChat.prompts)")
    precondition(!claudeChat.prompts[0].contains("geheim123"), "Prompts müssen redigiert sein")
    precondition(claudeChat.activeMinutes == 10, "Aktive Zeit: Lücke über 10 Min. zählt nicht (ist \(claudeChat.activeMinutes))")
    precondition(chats[1].tool == "Codex" && chats[1].branch == "main" && chats[1].prompts == ["Refactoring Service"])
    precondition(ChatActivity.read(day: "2026-10-26", repos: [], home: fakeHome).isEmpty, "Ohne getrackte Repos keine Chats")
    let evidence = ChatActivity.formatEvidence(chats)
    precondition(evidence.contains("Claude Code · App (feature/x) · 09:00–10:30"), "Zeiten in Europe/Berlin: \(evidence)")
    let builtInIds = AITools.builtIns().map(\.id)
    precondition(builtInIds == ["claude", "codex", "ollama"], "Eingebaute KI-Werkzeuge fehlen: \(builtInIds)")
    precondition(AITools.builtIns()[0].command.contains("--tools \"\"") && AITools.builtIns()[1].command.contains("read-only"),
                 "Claude ohne Werkzeuge, Codex nur lesend")
    let toolDir = FileManager.default.temporaryDirectory.appendingPathComponent("schichta-ai-tools-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: toolDir, withIntermediateDirectories: true)
    try #"{"name":"Mein LLM","command":"llm -m x"}"#.write(to: toolDir.appendingPathComponent("llm.json"), atomically: true, encoding: .utf8)
    try #"{"name":"kaputt"}"#.write(to: toolDir.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
    let loadedTools = AITools.load(folder: toolDir)
    try? FileManager.default.removeItem(at: toolDir)
    precondition(loadedTools.tools.count == 4 && loadedTools.tools[3].id == "file:llm" && loadedTools.tools[3].command == "llm -m x",
                 "Eigene Werkzeug-Datei nicht geladen (Beispieldatei darf nicht mitzählen)")
    precondition(loadedTools.errors.count == 1 && loadedTools.errors[0].contains("broken.json"))
    print("KI-Zusammenfassung ok")

    UserDefaults.standard.removePersistentDomain(forName: testDefaultsSuite)
    try? FileManager.default.removeItem(at: testStoreURL.deletingLastPathComponent())

    print("Desktop-Selbsttest erfolgreich!")
    exit(0)
} else if let idx = CommandLine.arguments.firstIndex(of: "--snapshot"), idx + 1 < CommandLine.arguments.count {
    // Dev-Werkzeug: rendert die wichtigsten Ansichten offscreen als PNG (Layout-Prüfung ohne Bildschirmaufnahme).
    let outDir = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    _ = NSApplication.shared
    let store = SchichtaStore()

    func render<V: View>(_ view: V, _ size: NSSize, _ name: String) {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: view)
            let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            win.appearance = NSAppearance(named: appearance)
            win.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("\(name)-\(suffix).png"))
        }
        print("\(name): fitting \(NSHostingView(rootView: view).fittingSize), rendered \(size)")
    }

    render(CheckInPopoverView(store: store, onClose: {}), NSSize(width: 380, height: 305), "popover")
    render(CheckInPopoverView(store: store, onClose: {}), NSSize(width: 380, height: 320), "checkin-panel")
    render(DatePickerPopoverContent(store: store, isPresented: .constant(true)), NSSize(width: 200, height: 230), "date-popover")
    render(MainWindowView(store: store), NSSize(width: 1220, height: 860), "main")
    render(MainWindowView(store: store), NSSize(width: 950, height: 650), "main-min")
    for tab in 0..<4 {
        store.settingsSelectedTab = tab
        render(SettingsView(store: store), NSSize(width: 720, height: 620), "settings-\(tab)")
    }
    exit(0)
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
