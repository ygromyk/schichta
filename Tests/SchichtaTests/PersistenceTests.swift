import Foundation
import Testing
@testable import Schichta

/// A temporary data folder, optionally pre-filled with `schichta.json`, and a store opened on it.
@MainActor
func withDataFolder(_ name: String = #function, contents: String? = nil, _ body: (URL, () -> SchichtaStore) throws -> Void) throws {
    let suite = "local.schichta.tests.persistence." + name.filter(\.isLetter)
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("schichta-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }
    let file = dir.appendingPathComponent("schichta.json")
    if let contents { try Data(contents.utf8).write(to: file) }
    try body(file) { SchichtaStore(storeURL: file, defaults: UserDefaults(suiteName: suite)!) }
}

@Suite("Persistence: the data file is never lost")
@MainActor
struct PersistenceTests {
    static let validFile = #"{"version":1,"entries":[{"id":"e1","date":"2026-10-26","ticket":"PROJ-1","description":"Work","minutes":60,"estimated":false}],"journal":{}}"#

    @Test func validFileLoads() throws {
        try withDataFolder(contents: Self.validFile) { _, open in
            let store = open()
            #expect(store.database.entries.map(\.id) == ["e1"])
            #expect(store.storeProblem == nil)
        }
    }

    @Test func notesTypedLastAreWrittenByFlush() throws {
        try withDataFolder { _, open in
            let store = open()
            store.updateJournalNotes("x")
            store.flushPendingSave()
            #expect(open().database.journal[store.selectedDay]?.notes == "x")
        }
    }

    @Test func aSyncSaveCarriesPendingNotes() throws {
        try withDataFolder { _, open in
            let store = open()
            store.updateJournalNotes("x")
            store.addEntry(ticket: "PROJ-1", description: "Work", minutes: 30, estimated: false)
            let reloaded = open()
            #expect(reloaded.database.journal[store.selectedDay]?.notes == "x")
            #expect(reloaded.database.entries.count == 1)
        }
    }

    @Test func missingFileStartsEmptyAndCreatesIt() throws {
        try withDataFolder { file, open in
            let store = open()
            #expect(store.database.entries.isEmpty)
            #expect(store.storeProblem == nil)
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test(arguments: [
        "{ not json",
        #"{"version":2,"entries":[],"journal":{}}"#,
        #"{"version":1,"entries":[{"id":"e1","date":"2026-02-30","ticket":"","description":"x","minutes":5,"estimated":false}],"journal":{}}"#,
    ])
    func unreadableFileIsMovedAsideNotOverwritten(contents: String) throws {
        try withDataFolder(contents: contents) { file, open in
            let store = open()
            #expect(store.database.entries.isEmpty)
            #expect(store.storeProblem != nil)
            #expect(!store.savingBlocked)

            let dir = file.deletingLastPathComponent()
            let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("schichta.unreadable-") }
            #expect(aside.count == 1)
            #expect(try String(contentsOf: dir.appendingPathComponent(aside[0]), encoding: .utf8) == contents, "kept byte for byte")

            // New work goes into a fresh schichta.json, never into the moved file.
            store.addEntry(ticket: "", description: "After recovery", minutes: 30, estimated: false)
            #expect(try String(contentsOf: dir.appendingPathComponent(aside[0]), encoding: .utf8) == contents)
            #expect(try String(contentsOf: file, encoding: .utf8).contains("After recovery"))
        }
    }

    @Test func newerFormatExplainsItself() throws {
        try withDataFolder(contents: #"{"version":2,"entries":[],"journal":{}}"#) { _, open in
            let problem = try #require(open().storeProblem)
            #expect(problem.localizedCaseInsensitiveContains("format 2"), "says why, in the store's language")
            let error = try #require(throws: SchichtaError.self) { try SchichtaCore.validate(database: Database(version: 2)) }
            #expect(error.text.en.contains("newer Schichta version"))
            #expect(error.text.de.contains("neueren Schichta-Version"))
        }
    }

    @Test func firstSaveOfADayKeepsABackupAndOldOnesArePruned() throws {
        try withDataFolder(contents: Self.validFile) { file, _ in
            let dbFile = DatabaseFile(url: file, keptBackups: 2)
            var db = try #require({ if case .loaded(let d) = dbFile.load() { d } else { nil } }())

            db.entries[0].minutes = 90
            try dbFile.save(db, today: "2026-10-24")
            db.entries[0].minutes = 120
            try dbFile.save(db, today: "2026-10-24") // same day: backup stays the pre-day state
            try dbFile.save(db, today: "2026-10-25")
            try dbFile.save(db, today: "2026-10-26")

            let names = try FileManager.default.contentsOfDirectory(atPath: dbFile.backupsDirectory.path).sorted()
            #expect(names == ["schichta-2026-10-25.json", "schichta-2026-10-26.json"])
            let oldest = try JSONDecoder().decode(Database.self, from: Data(contentsOf: dbFile.backupsDirectory.appendingPathComponent(names[0])))
            #expect(oldest.entries[0].minutes == 120)
        }
    }
}
