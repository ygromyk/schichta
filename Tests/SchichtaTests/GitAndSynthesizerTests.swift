import Foundation
import Testing
@testable import Schichta

@Suite("Git activity")
struct GitActivityTests {
    @Test func dayBoundsCoverTheDSTSwitch() throws {
        let bounds = try Activity.bounds("2026-10-25")
        #expect(bounds.0 == "2026-10-25T00:00:00+02:00")
        #expect(bounds.1 == "2026-10-25T23:59:59+01:00")
        #expect(throws: (any Error).self) { try Activity.bounds("2026-02-30") }
    }

    @Test func nothingIsReadWithoutTrackedRepos() throws {
        let result = try Activity.readRepos("2026-10-12", repos: [], authorFilter: nil)
        #expect((result["repositories"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test func missingReposReportMetadataAndAnError() throws {
        let repos = [
            TrackedRepo(path: "/nonexistent/example-app", projectName: "Example App", defaultTicket: "PROJ-2800", enabled: true),
            TrackedRepo(path: "/nonexistent/example-api", projectName: "", defaultTicket: "", enabled: true),
        ]
        let result = try Activity.readRepos("2026-10-12", repos: repos, authorFilter: "Max Mustermann")
        let data = try #require(result["repositories"] as? [[String: Any]])
        #expect(data.count == 2)
        #expect(data[0]["projectName"] as? String == "Example App")
        #expect(data[0]["defaultTicket"] as? String == "PROJ-2800")
        #expect(data[0]["error"] is String)
    }
}

@Suite("Automatic proposals")
struct AutoSynthesizerTests {
    let journal = JournalItem(
        notes: "- 09:30 (30 Min.): [PROJ-2800] Replay testen\n- 10:00 (30 Min.): [PROJ-2800] Replay testen\n- 11:30 (30 Min.): [PROJ-2900] Architektur\nTeam-Meeting 45m",
        logs: "", answer: ""
    )
    let gitResult: [String: Any] = [
        "repositories": [[
            "repository": "example-app",
            "commits": ["text": "abc1234 | Autorzeit: 2026-10-26T10:00:00+02:00 | Commitzeit: 2026-10-26T10:00:00+02:00 | feat: PROJ-3000 Fix timing in order controller\ndef5678 | Autorzeit: 2026-10-26T11:00:00+02:00 | Commitzeit: 2026-10-26T11:00:00+02:00 | fix: PROJ-3000 Add order unit tests"],
        ]],
    ]

    func proposals(existing: [Entry] = []) -> [ProposedEntry] {
        AutoSynthesizer.synthesizeDay(day: "2026-10-26", journal: journal, gitResult: gitResult, existingEntries: existing)
    }

    @Test func repeatedCheckInsAreSummed() throws {
        let replay = try #require(proposals().first(where: { $0.ticket == "PROJ-2800" }))
        #expect(replay.minutes == 60)
        #expect(replay.source == "Aus 30m Check-ins")
    }

    @Test func durationsInFreeTextNotesAreRecognized() throws {
        let meeting = try #require(proposals().first(where: { $0.description.contains("Team-Meeting") }))
        #expect(meeting.minutes == 45)
        #expect(meeting.source == "Aus Tagesnotiz")
    }

    @Test func commitsAreGroupedByTicket() throws {
        let git = try #require(proposals().first(where: { $0.ticket == "PROJ-3000" }))
        #expect(git.description.contains("example-app: Fix timing in order controller, Add order unit tests"))
        #expect(git.source == "Git · example-app")
    }

    @Test func alreadyRecordedWorkIsNotProposedAgain() {
        let existing = [Entry(id: "ex1", date: "2026-10-26", ticket: "PROJ-2800", description: "Replay testen", minutes: 60, estimated: false)]
        #expect(!proposals(existing: existing).contains(where: { $0.ticket == "PROJ-2800" }))
    }

    @Test func repoProjectNameDefaultTicketAndWorkingTree() throws {
        let result: [String: Any] = [
            "repositories": [
                [
                    "repository": "example-app", "projectName": "Example App", "defaultTicket": "PROJ-2800",
                    "commits": ["text": "c1a2b3c | Autorzeit: 2026-10-26T14:00:00+02:00 | Commitzeit: 2026-10-26T14:00:00+02:00 | Refactor connection handler"],
                ],
                [
                    "repository": "example-api", "projectName": "Example API", "defaultTicket": "PROJ-1000",
                    "commits": ["text": ""],
                    "head_activity": ["text": "reflog 1 | commit: checkout branch PROJ-5555"],
                    "working_tree": ["text": " M src/index.ts\n M src/controller.ts\n"],
                ],
            ],
        ]
        let found = AutoSynthesizer.synthesizeDay(day: "2026-10-26", journal: JournalItem(), gitResult: result, existingEntries: [])

        let defaultTicket = try #require(found.first(where: { $0.ticket == "PROJ-2800" }))
        #expect(defaultTicket.description.hasPrefix("Example App:"))
        #expect(defaultTicket.project == "Example App")

        let workingTree = try #require(found.first(where: { $0.description.contains("Lokale Änderungen") }))
        #expect(workingTree.description.contains("Example API: Lokale Änderungen (2 Dateien in Arbeit)"))
        #expect(workingTree.minutes == 30)
        #expect(workingTree.ticket == "PROJ-5555", "ticket from the checked-out branch")
    }
}
