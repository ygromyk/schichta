import Foundation
import Testing
@testable import Schichta

@Suite("Parsing and formatting")
struct CoreTests {
    @Test("Durations parse from HH:MM, decimal hours and unit suffixes", arguments: [
        ("1:30", 90), ("01:05", 65), ("1,5", 90), ("1.25", 75),
        ("30m", 30), ("45 min", 45), ("2h", 120), ("1,5h", 90),
    ])
    func parsesDurations(input: String, minutes: Int) throws {
        #expect(try SchichtaCore.parseMinutes(input) == minutes)
    }

    @Test("Invalid durations are rejected", arguments: ["1:60", "-2", "0", "1:2", "abc", "24:01", "1,5abc"])
    func rejectsInvalidDurations(input: String) {
        #expect(throws: (any Error).self) { try SchichtaCore.parseMinutes(input) }
    }

    @Test("Durations snap to the nearest step, at least one step, at most 24 hours", arguments: [
        (22, 15, 15), (23, 15, 30), (65, 15, 60), (68, 15, 75), (0, 15, 15), (-10, 15, 15),
        (1500, 15, 1440), (44, 30, 30), (45, 30, 60), (5, 10, 10), (1439, 60, 1440), (7, 1, 7),
    ])
    func snapsDurations(minutes: Int, step: Int, expected: Int) {
        #expect(SchichtaCore.snapDuration(minutes, step: step) == expected)
    }

    @Test func labelsDurations() {
        #expect(SchichtaCore.durationLabel(15) == "15m")
        #expect(SchichtaCore.durationLabel(60) == "1h")
        #expect(SchichtaCore.durationLabel(90) == "1,5h")
        #expect(SchichtaCore.durationLabel(80) == "01:20")
    }

    @Test func formatsTimesAndDates() {
        #expect(SchichtaCore.formatTime(90) == "01:30")
        #expect(SchichtaCore.formatTime(65) == "01:05")
        #expect(SchichtaCore.formatGermanDate("2026-10-26") == "26.10.2026")
    }

    @Test func appendsCheckInLines() throws {
        let first = try SchichtaCore.appendCheckIn(existingNotes: "", timeStr: "12:30", text: "Replay getestet")
        #expect(first == "- 12:30 (30 Min.): Replay getestet")

        let second = try SchichtaCore.appendCheckIn(existingNotes: first, timeStr: "13:00", text: "Abstimmung mit dem Team", ticket: "proj-2800")
        #expect(second == "- 12:30 (30 Min.): Replay getestet\n- 13:00 (30 Min.): [PROJ-2800] Abstimmung mit dem Team")

        let custom = try SchichtaCore.appendCheckIn(existingNotes: "", timeStr: "14:00", text: "Sprint Planning", ticket: "proj-2900", minutes: 45)
        #expect(custom == "- 14:00 (45 Min.): [PROJ-2900] Sprint Planning")

        #expect(throws: (any Error).self) { try SchichtaCore.appendCheckIn(existingNotes: "", timeStr: "12:30", text: "   ") }
    }

    @Test func checkInWindowShowsInterval() {
        let now = Date()
        #expect(AppDelegate.checkInWindowString(for: now, intervalMinutes: 15).contains("· 15 Min. Check-in"))
        #expect(AppDelegate.checkInWindowString(for: now, intervalMinutes: 60).contains("· 60 Min. Check-in"))
        #expect(AppDelegate.checkInWindowString(for: now, intervalMinutes: 15, language: .en).contains("· 15 min check-in"))
    }

    @Test func checkInModeTitlesAreLocalized() {
        #expect(CheckInMode.both.title(for: .de) == "Als Eintrag + Notiz")
        #expect(CheckInMode.noteOnly.title(for: .de) == "Nur als Notiz")
        #expect(CheckInMode.both.title(for: .en) == "As entry + note")
        #expect(CheckInMode.noteOnly.title(for: .en) == "Note only")
    }

    @Test func bookingReportListsEntriesAndMarksEstimates() {
        let entries = [
            Entry(id: "1", date: "2026-10-26", ticket: "PROJ-2800", description: "Replay prüfen", minutes: 90, estimated: true),
            Entry(id: "2", date: "2026-10-26", ticket: "", description: "Abstimmung", minutes: 15, estimated: false),
        ]
        let report = SchichtaCore.bcsReport(day: "2026-10-26", entries: entries)
        #expect(report.contains("Datum: 26.10.2026"))
        #expect(report.contains("Gesamtzeit: 01:45"))
        #expect(report.contains("1. Replay prüfen"))
        #expect(report.contains("Ticket: PROJ-2800"))
        #expect(report.contains("Dauer: 01:30 (Schätzung – prüfen)"))
        #expect(report.contains("Ticket: Ohne Ticket"))
    }
}

@Suite("Data model and backups")
struct ModelTests {
    @Test func validDatabasePassesValidationAndKeepsBookedFlag() throws {
        let db = Database(version: 1, entries: [
            Entry(id: "e1", date: "2026-10-23", ticket: "PROJ-1", description: "Test", minutes: 30, estimated: false),
        ], journal: ["2026-10-23": JournalItem(notes: "Notiz", logs: "Log", answer: "", booked: true)])
        #expect(try SchichtaCore.validate(database: db).journal["2026-10-23"]?.booked == true)
    }

    @Test func journalItemsWithoutBookedFieldDecode() throws {
        let old = try JSONDecoder().decode(JournalItem.self, from: Data(#"{"notes":"Tagesnotiz","logs":"","answer":""}"#.utf8))
        #expect(old.booked == false)
        let new = try JSONDecoder().decode(JournalItem.self, from: Data(#"{"notes":"Tagesnotiz","logs":"","answer":"","booked":true}"#.utf8))
        #expect(new.booked == true)
    }

    @Test func entriesWithoutProjectDecode() throws {
        let json = #"{"id":"old-entry-1","date":"2026-10-26","ticket":"PROJ-10","description":"Old JSON without project","minutes":45,"estimated":false}"#
        #expect(try JSONDecoder().decode(Entry.self, from: Data(json.utf8)).project == "")
    }

    @Test func trackedRepoLabelsAndCoding() throws {
        let named = TrackedRepo(path: "/Users/me/Projects/example-app", projectName: "Example App", defaultTicket: "PROJ-2800", enabled: true)
        let unnamed = TrackedRepo(path: "/Users/me/Projects/example-api", projectName: "", defaultTicket: "", enabled: true)
        #expect(named.folderName == "example-app")
        #expect(named.displayLabel == "Example App")
        #expect(unnamed.displayLabel == "example-api")

        let decoded = try JSONDecoder().decode([TrackedRepo].self, from: JSONEncoder().encode([named, unnamed]))
        #expect(decoded.count == 2 && decoded[0].projectName == "Example App")
    }

    @Test func hookPayloadAssignsProjects() {
        let repos = [
            TrackedRepo(path: "/Users/me/Projects/example-app", projectName: "Example App", defaultTicket: "PROJ-2800", enabled: true),
            TrackedRepo(path: "/Users/me/Projects/example-api", projectName: "", defaultTicket: "", enabled: true),
        ]
        let entries = [
            Entry(id: "h1", date: "2026-10-26", ticket: "PROJ-2800", description: "Example App: Replay prüfen", minutes: 60, estimated: false),
            Entry(id: "h2", date: "2026-10-26", ticket: "PROJ-9999", description: "Example API: CI fix", minutes: 30, estimated: true),
            Entry(id: "h3", date: "2026-10-26", ticket: "", description: "Team Meeting", minutes: 30, estimated: false, project: "Custom Org"),
        ]
        let payload = SchichtaCore.buildHookPayload(day: "2026-10-26", entries: entries, repos: repos, author: "Max Mustermann")
        #expect(payload.event == "day_booked")
        #expect(payload.date == "2026-10-26")
        #expect(payload.totalMinutes == 120)
        #expect(payload.totalFormatted == "02:00")

        let projects = payload.entries.map(\.projectName)
        #expect(projects == ["Example App", "example-api", "Custom Org"], "default-ticket match, folder prefix, explicit project")
    }
}

@Suite("Languages")
@MainActor
struct LanguageTests {
    @Test func errorsCarryBothLanguages() throws {
        let error = try #require(throws: SchichtaError.self) { try SchichtaCore.parseMinutes("abc") }
        #expect(error.text.de == "Dauer als 1:30, 1,5 oder 30m eingeben.")
        #expect(error.text.en == "Enter the duration as 1:30, 1.5 or 30m.")
    }

    @Test func storeDescribesErrorsInItsLanguage() {
        withTestStore { store in
            let error = SchichtaError("git.invalidDate")
            store.appLanguage = .en
            #expect(store.describe(error) == "Invalid date")
            store.appLanguage = .de
            #expect(store.describe(error) == "Ungültiges Datum")
        }
    }

    @Test func proposalTextsFollowTheLanguage() throws {
        let gitResult = GitActivityResult(date: "2026-10-26", timezone: "UTC", repositories: [
            RepoActivity(folderName: "example-app", workingTree: GitOutput(text: " M a.swift\n")),
        ])
        let en = AutoSynthesizer.synthesizeDay(day: "2026-10-26", journal: JournalItem(), gitResult: gitResult, existingEntries: [], language: .en)
        #expect(en.first?.description == "example-app: Local changes (1 files in progress)")
        #expect(en.first?.source.en == "Git · example-app (local changes)")
    }
}

@Suite("Hook payload format")
struct HookPayloadTests {
    /// Shell hooks and webhooks parse this JSON. If this test fails, a field was renamed or removed: external
    /// scripts would break. Add new fields to the expectation instead of changing existing ones.
    @Test func jsonFieldsStayStable() throws {
        let payload = SchichtaCore.buildHookPayload(
            day: "2026-10-26",
            entries: [Entry(id: "h1", date: "2026-10-26", ticket: "PROJ-2800", description: "Replay prüfen", minutes: 90, estimated: true)],
            repos: [TrackedRepo(path: "/Users/me/Projects/example-app", projectName: "Example App", defaultTicket: "PROJ-2800", enabled: true)],
            author: "Max Mustermann")
        let expected = #"""
        {
          "author": "Max Mustermann",
          "bcsReport": "Datum: 26.10.2026\nGesamtzeit: 01:30\n\n1. Replay prüfen\nTicket: PROJ-2800\nDauer: 01:30 (Schätzung – prüfen)",
          "date": "2026-10-26",
          "dateFormatted": "26.10.2026",
          "entries": [{
            "date": "2026-10-26", "description": "Replay prüfen", "durationFormatted": "01:30", "estimated": true,
            "id": "h1", "minutes": 90, "projectName": "Example App", "ticket": "PROJ-2800"
          }],
          "event": "day_booked",
          "repositories": [{
            "defaultTicket": "PROJ-2800", "displayLabel": "Example App", "enabled": true, "folder": "example-app",
            "path": "/Users/me/Projects/example-app", "projectName": "Example App"
          }],
          "totalFormatted": "01:30",
          "totalMinutes": 90
        }
        """#
        let actual = try #require(try JSONSerialization.jsonObject(with: payload.json()) as? NSDictionary)
        let golden = try #require(try JSONSerialization.jsonObject(with: Data(expected.utf8)) as? NSDictionary)
        #expect(actual == golden)
        let text = String(decoding: try payload.json(), as: UTF8.self)
        #expect(text.contains(#""estimated" : true"#), "booleans stay JSON booleans")
    }
}
