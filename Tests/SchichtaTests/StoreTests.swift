import Foundation
import Testing
@testable import Schichta

/// A store on a temporary file and its own user-defaults domain, so tests never touch real entries or settings.
/// Each test passes its own `name`, which keeps parallel tests apart.
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
        withTestStore { store in
            store.workStartHour = 9; store.workStartMinute = 0
            store.workEndHour = 17; store.workEndMinute = 0
            store.onlyPromptDuringWorkHours = true
            func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
                Berlin.calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
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

    @Test func settingsViewBuilds() {
        withTestStore { store in
            _ = SettingsView(store: store)
        }
    }
}
