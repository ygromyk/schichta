import Foundation
import Testing
@testable import Schichta

/// Tests with Berlin-specific expectations pin the app zone. No test pins any other zone,
/// so tests running in parallel always agree on it.
func pinBerlin() {
    AppTime.use(TimeZone(identifier: "Europe/Berlin")!)
}

@Suite("Time zone")
struct TimeZoneTests {
    @Test func dayBoundsCoverTheDSTSwitch() throws {
        let berlin = AppTime.State(TimeZone(identifier: "Europe/Berlin")!)
        let bounds = try Activity.bounds("2026-10-25", in: berlin)
        #expect(bounds.0 == "2026-10-25T00:00:00+02:00")
        #expect(bounds.1 == "2026-10-25T23:59:59+01:00", "25 hours: clocks go back")
        #expect(throws: (any Error).self) { try Activity.bounds("2026-02-30", in: berlin) }
    }

    @Test func dayBoundsFollowTheConfiguredZone() throws {
        let newYork = AppTime.State(TimeZone(identifier: "America/New_York")!)
        let bounds = try Activity.bounds("2026-10-26", in: newYork)
        #expect(bounds.0 == "2026-10-26T00:00:00-04:00")
        #expect(bounds.1 == "2026-10-26T23:59:59-04:00")
        // 23:30 in New York is already the next day in Berlin.
        let lateEvening = try #require(newYork.isoSeconds.date(from: "2026-10-26T23:30:00-04:00"))
        #expect(newYork.day.string(from: lateEvening) == "2026-10-26")
        #expect(AppTime.State(TimeZone(identifier: "Europe/Berlin")!).day.string(from: lateEvening) == "2026-10-27")
    }

    @Test func emptySettingMeansSystemZone() {
        #expect(AppTime.zone(forIdentifier: "") == TimeZone.current)
        #expect(AppTime.zone(forIdentifier: "Asia/Tokyo").identifier == "Asia/Tokyo")
        #expect(AppTime.zone(forIdentifier: "Not/AZone") == TimeZone.current, "unknown identifiers fall back to the system zone")
    }
}

@Suite("Git activity")
struct GitActivityTests {

    @Test func nothingIsReadWithoutTrackedRepos() throws {
        let result = try Activity.readRepos("2026-10-12", repos: [], authorFilter: nil)
        #expect(result.repositories.isEmpty)
    }

    @Test func missingReposReportMetadataAndAnError() throws {
        let repos = [
            TrackedRepo(path: "/nonexistent/example-app", projectName: "Example App", defaultTicket: "PROJ-2800", enabled: true),
            TrackedRepo(path: "/nonexistent/example-api", projectName: "", defaultTicket: "", enabled: true),
        ]
        let result = try Activity.readRepos("2026-10-12", repos: repos, authorFilter: "Max Mustermann")
        let data = result.repositories
        #expect(data.count == 2)
        #expect(data[0].projectName == "Example App")
        #expect(data[0].defaultTicket == "PROJ-2800")
        #expect(data[0].error?.en == "Directory not found: /nonexistent/example-app")
        #expect(data[1].title == "example-api")
    }
}

@Suite("Automatic proposals")
struct AutoSynthesizerTests {
    let journal = JournalItem(
        notes: "- 09:30 (30 Min.): [PROJ-2800] Replay testen\n- 10:00 (30 Min.): [PROJ-2800] Replay testen\n- 11:30 (30 Min.): [PROJ-2900] Architektur\nTeam-Meeting 45m",
        logs: "", answer: ""
    )
    let gitResult = GitActivityResult(date: "2026-10-26", timezone: "Europe/Berlin", repositories: [
        RepoActivity(folderName: "example-app", commits: GitOutput(text: "abc1234 | Autorzeit: 2026-10-26T10:00:00+02:00 | Commitzeit: 2026-10-26T10:00:00+02:00 | feat: PROJ-3000 Fix timing in order controller\ndef5678 | Autorzeit: 2026-10-26T11:00:00+02:00 | Commitzeit: 2026-10-26T11:00:00+02:00 | fix: PROJ-3000 Add order unit tests")),
    ])

    func proposals(existing: [Entry] = []) -> [ProposedEntry] {
        AutoSynthesizer.synthesizeDay(day: "2026-10-26", journal: journal, gitResult: gitResult, existingEntries: existing)
    }

    @Test func repeatedCheckInsAreSummed() throws {
        let replay = try #require(proposals().first(where: { $0.ticket == "PROJ-2800" }))
        #expect(replay.minutes == 60)
        #expect(replay.source.de == "Aus Check-ins")
    }

    @Test func durationsInFreeTextNotesAreRecognized() throws {
        let meeting = try #require(proposals().first(where: { $0.description.contains("Team-Meeting") }))
        #expect(meeting.minutes == 45)
        #expect(meeting.source.de == "Aus Tagesnotiz")
    }

    @Test func commitsAreGroupedByTicket() throws {
        let git = try #require(proposals().first(where: { $0.ticket == "PROJ-3000" }))
        #expect(git.description.contains("example-app: Fix timing in order controller, Add order unit tests"))
        #expect(git.source.en == "Git · example-app")
    }

    @Test func alreadyRecordedWorkIsNotProposedAgain() {
        let existing = [Entry(id: "ex1", date: "2026-10-26", ticket: "PROJ-2800", description: "Replay testen", minutes: 60, estimated: false)]
        #expect(!proposals(existing: existing).contains(where: { $0.ticket == "PROJ-2800" }))
    }

    @Test func repoProjectNameDefaultTicketAndWorkingTree() throws {
        let result = GitActivityResult(date: "2026-10-26", timezone: "Europe/Berlin", repositories: [
            RepoActivity(folderName: "example-app", projectName: "Example App", defaultTicket: "PROJ-2800",
                         commits: GitOutput(text: "c1a2b3c | Autorzeit: 2026-10-26T14:00:00+02:00 | Commitzeit: 2026-10-26T14:00:00+02:00 | Refactor connection handler")),
            RepoActivity(folderName: "example-api", projectName: "Example API", defaultTicket: "PROJ-1000",
                         headActivity: GitOutput(text: "reflog 1 | commit: checkout branch PROJ-5555"),
                         workingTree: GitOutput(text: " M src/index.ts\n M src/controller.ts\n")),
        ])
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
