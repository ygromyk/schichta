import Foundation
import Testing
@testable import Schichta

/// A store on a temporary file and its own user-defaults domain, so tests never touch real entries or settings.
/// Each test passes its own `name`, which keeps parallel tests apart.
@MainActor
func withTestStore(_ name: String = #function, _ body: (SchichtaStore) throws -> Void) rethrows {
    let suite = "local.schichta.tests." + name.filter(\.isLetter)
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("schichta-tests-\(UUID().uuidString)")
    defer {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }
    try body(SchichtaStore(storeURL: dir.appendingPathComponent("schichta.json"), defaults: UserDefaults(suiteName: suite)!))
}

@Suite("Store: booking status and working days")
@MainActor
struct StoreTests {
    @Test func unbookedDaysAndPreviousWorkingDay() {
        withTestStore { store in
            store.database = Database(version: 1, entries: [
                Entry(id: "e_fri", date: "2026-10-23", ticket: "PROJ-2800", description: "Freitag Arbeit", minutes: 60, estimated: false),
            ], journal: [
                "2026-10-23": JournalItem(notes: "Freitagsnotiz", logs: "", answer: "", booked: false),
                "2026-10-22": JournalItem(notes: "Donnerstag", logs: "", answer: "", booked: true),
            ])
            #expect(store.isDayUnbooked("2026-10-23"))
            #expect(!store.isDayUnbooked("2026-10-22"), "booked days are not unbooked")
            #expect(store.previousWorkingDay(before: "2026-10-26") == "2026-10-23")

            store.markDayBooked("2026-10-23", booked: true)
            #expect(store.database.journal["2026-10-23"]?.booked == true)
            #expect(!store.isDayUnbooked("2026-10-23"))
        }
    }

    @Test func unbookedPreviousDaySkipsWeekends() {
        withTestStore { store in
            store.database = Database(version: 1, entries: [], journal: [
                "2026-10-25": JournalItem(notes: "Sonntagsnotiz", logs: "", answer: "", booked: false),
                "2026-10-24": JournalItem(notes: "Samstagsnotiz", logs: "", answer: "", booked: false),
                "2026-10-23": JournalItem(notes: "Freitagsarbeit", logs: "", answer: "", booked: false),
                "2026-10-22": JournalItem(notes: "Donnerstag", logs: "", answer: "", booked: true),
            ])
            #expect(store.unbookedPreviousDay(today: "2026-10-26") == "2026-10-23")
        }
    }

    @Test func workingDaysAreConfigurable() {
        withTestStore { store in
            #expect(store.workingDays == [2, 3, 4, 5, 6], "Monday to Friday by default")
            #expect(store.isWorkingDay("2026-10-26"))
            #expect(store.isWorkingDay("2026-10-23"))
            #expect(!store.isWorkingDay("2026-10-24"))
            #expect(!store.isWorkingDay("2026-10-25"))

            store.workingDays = [7]
            #expect(store.isWorkingDay("2026-10-24"))
            #expect(!store.isWorkingDay("2026-10-26"))
        }
    }

    @Test func promptsOnlyDuringWorkingHours() {
        pinBerlin()
        withTestStore { store in
            store.workStartHour = 9; store.workStartMinute = 0
            store.workEndHour = 17; store.workEndMinute = 0
            store.onlyPromptDuringWorkHours = true
            func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
                AppTime.calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
            }
            #expect(store.isCurrentlyWithinWorkingHours(at(26, 10, 30)))
            #expect(!store.isCurrentlyWithinWorkingHours(at(26, 8, 30)))
            #expect(!store.isCurrentlyWithinWorkingHours(at(26, 17, 30)))
            #expect(!store.isCurrentlyWithinWorkingHours(at(25, 14, 0)), "Sunday")
        }
    }

    @Test func defaultsAndLanguageSwitch() {
        withTestStore { store in
            #expect(store.reminderIntervalMinutes == 15)
            #expect(store.checkInSoundEnabled)
            #expect(store.checkInSoundName == "Glass")
            #expect(SchichtaStore.availableSounds.contains("Hero"))

            store.appLanguage = .de
            #expect(store.t("Heute", "Today") == "Heute")
            #expect(SchichtaCore.formatFullDate("2026-10-26", language: .de).contains("Montag"))
            store.appLanguage = .en
            #expect(store.t("Heute", "Today") == "Today")
            #expect(SchichtaCore.formatFullDate("2026-10-26", language: .en).contains("Monday"))
        }
    }

    @Test func settingsKeepTheirStoredFormat() throws {
        withTestStore { store in
            store.appLanguage = .en
            store.defaultCheckInMode = .noteOnly
            store.workingDays = [6, 2]
            store.trackedRepos = [TrackedRepo(path: "/tmp/example-app", projectName: "Example", defaultTicket: "", enabled: true)]
            #expect(store.defaults.string(forKey: "Schichta.AppLanguage") == "en", "enums as raw strings")
            #expect(store.defaults.string(forKey: "Schichta.DefaultCheckInMode") == "noteOnly")
            #expect(store.defaults.array(forKey: "Schichta.WorkingDays") as? [Int] == [2, 6])
            let data = store.defaults.data(forKey: "Schichta.TrackedReposV1") ?? Data()
            #expect((try? JSONDecoder().decode([TrackedRepo].self, from: data))?.first?.projectName == "Example")

            store.trackedRepos[0].enabled = false
            #expect(store.trackedRepos[0].enabled == false, "element edits through bindings are saved")
        }
    }

    @Test func settingsAreClampedAndBadValuesFallBack() {
        withTestStore { store in
            store.reminderIntervalMinutes = 1
            #expect(store.reminderIntervalMinutes == 5)
            store.defaults.set(9999, forKey: "Schichta.DailyTargetMinutes")
            #expect(store.dailyTargetMinutes == 1440, "out-of-range stored values are clamped on read")
            store.defaults.set("klingon", forKey: "Schichta.AppLanguage")
            #expect(store.appLanguage == .system, "unknown values read as the default")
            store.defaults.set([Int](), forKey: "Schichta.WorkingDays")
            #expect(store.workingDays == [2, 3, 4, 5, 6])
        }
    }

    @Test func legacyWorkEndKeysAreMigrated() {
        let suite = "local.schichta.tests.legacyWorkEnd"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(18, forKey: "Schichta.EndOfDayPromptHour")
        defaults.set(30, forKey: "Schichta.EndOfDayPromptMinute")
        SchichtaStore.prepareDefaults(defaults)
        #expect(defaults.integer(forKey: "Schichta.WorkEndHour") == 18)
        #expect(defaults.integer(forKey: "Schichta.WorkEndMinute") == 30)
    }

    @Test func settingsViewBuilds() {
        withTestStore { store in
            _ = SettingsView(store: store)
        }
    }

    @Test func everyDurationFollowsTheTimeStep() throws {
        try withTestStore { store in
            #expect(store.timeStepMinutes == 15, "default")
            store.timeStepMinutes = 7
            #expect(store.timeStepMinutes == 15, "only offered steps are kept")
            store.selectDay("2026-10-26")

            store.addEntry(ticket: "PROJ-1", description: "Typed 0:50", minutes: 50, estimated: false)
            let id = try #require(store.entriesForSelectedDay().first?.id)
            #expect(store.entriesForSelectedDay().first?.minutes == 45)

            store.adjustEntryMinutes(id: id, steps: 2)
            #expect(store.entriesForSelectedDay().first?.minutes == 75)
            store.setEntryMinutes(id: id, minutes: 83)
            #expect(store.entriesForSelectedDay().first?.minutes == 90)

            store.timeStepMinutes = 30
            store.updateEntry(id: id, ticket: "PROJ-1", description: "Edited", minutes: 100, estimated: false)
            #expect(store.entriesForSelectedDay().first?.minutes == 90)
            #expect(store.durationPresets == [30, 60, 90, 120])
        }
    }

    @Test func proposalsAndCheckInsAreRounded() {
        withTestStore { store in
            store.selectDay(SchichtaCore.day())
            store.handleCheckIn(text: "Review", ticket: "", mode: .both, timeStr: "10:00", minutes: 20)
            #expect(store.entriesForSelectedDay().first?.minutes == 15)

            let open = ProposedEntry(id: "ai-0", ticket: "", description: "Unclear", minutes: 0, source: LocalizedText("KI", "AI"))
            let timed = ProposedEntry(id: "ai-1", ticket: "", description: "Fix", minutes: 52, source: LocalizedText("KI", "AI"))
            store.applyAISummary(AISummary.Result(summary: "", proposals: [open, timed], questions: []), day: store.selectedDay)
            #expect(store.proposals.map(\.minutes) == [0, 45], "time open stays open")
        }
    }
}
