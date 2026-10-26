import Foundation
import Testing
@testable import Schichta

@Suite("Days off")
@MainActor
struct AbsenceTests {
    @Test func aDayOffHasNoTargetAndNoReminders() {
        pinBerlin()
        withTestStore { store in
            store.dailyTargetMinutes = 480
            #expect(store.isWorkingDay("2026-10-27"))
            store.setAbsence(.vacation, on: "2026-10-27")
            #expect(!store.isWorkingDay("2026-10-27"), "prompts, lunch and check-ins all go by this")
            #expect(store.isScheduledWorkday("2026-10-27"), "still a Tuesday")

            let week = store.weekSummary(containing: "2026-10-27", today: "2026-10-29")
            let tuesday = week.days[1]
            #expect(tuesday.absence == .vacation && tuesday.target == 0 && !tuesday.isUnbooked)
            #expect(week.target == 4 * 480)
            #expect(week.unbookedDays == ["2026-10-26", "2026-10-28"])
            #expect(store.unbookedPreviousDay(today: "2026-10-28") == "2026-10-26", "the morning prompt skips the vacation day")

            store.setAbsence(nil, on: "2026-10-27")
            #expect(store.isWorkingDay("2026-10-27"))
        }
    }

    @Test func absenceIsSavedAndUnknownKindsDoNotBreakTheFile() throws {
        let item = JournalItem(absence: .sick)
        let decoded = try JSONDecoder().decode(JournalItem.self, from: JSONEncoder().encode(item))
        #expect(decoded.absence == .sick)
        let newer = try JSONDecoder().decode(JournalItem.self, from: Data(#"{"notes":"x","absence":"sabbatical"}"#.utf8))
        #expect(newer.absence == nil && newer.notes == "x", "a kind from a newer version reads as no absence")
        let old = try JSONDecoder().decode(JournalItem.self, from: Data(#"{"notes":"x"}"#.utf8))
        #expect(old.absence == nil)
    }
}

@Suite("Overtime account")
@MainActor
struct OvertimeTests {
    @Test func balanceRunsFromTheStartDateWithOpeningBalance() {
        pinBerlin()
        withTestStore { store in
            store.dailyTargetMinutes = 480
            store.database.entries = [
                Entry(id: "a", date: "2026-10-19", ticket: "", description: "Mon", minutes: 540, estimated: false),
                Entry(id: "b", date: "2026-10-26", ticket: "", description: "Mon", minutes: 480, estimated: false),
            ]
            // From the first entry (Mon 19 Oct) to Mon 26 Oct: 6 working days, 1020 logged.
            #expect(store.overtimeStart(today: "2026-10-26") == "2026-10-19")
            #expect(store.overtimeBalance(today: "2026-10-26") == 1020 - 6 * 480)

            store.overtimeStartDate = "2026-10-26"
            store.overtimeOpeningMinutes = 750
            #expect(store.overtimeBalance(today: "2026-10-26") == 750, "on target from the start date, plus the opening balance")

            store.setAbsence(.holiday, on: "2026-10-27")
            #expect(store.overtimeBalance(today: "2026-10-27") == 750, "a holiday costs nothing")
        }
    }

    @Test func signedHoursParseAndFormat() {
        #expect(SchichtaCore.parseSignedHours("+12:30") == 750)
        #expect(SchichtaCore.parseSignedHours("-4:00") == -240)
        #expect(SchichtaCore.parseSignedHours("−1,5") == -90)
        #expect(SchichtaCore.parseSignedHours("40h") == 2400)
        #expect(SchichtaCore.parseSignedHours("abc") == nil)
        #expect(SchichtaCore.formatSignedTime(-90) == "−01:30")
        #expect(SchichtaCore.formatSignedTime(0) == "+00:00")
    }
}

@Suite("Month export")
@MainActor
struct MonthExportTests {
    @Test func csvHasOneRowPerEntryAndDayOff() {
        pinBerlin()
        withTestStore { store in
            store.appLanguage = .de
            store.database.entries = [
                Entry(id: "a", date: "2026-10-26", ticket: "PROJ-1", description: "Review; Teil \"2\"", minutes: 90, estimated: true),
                Entry(id: "b", date: "2026-10-02", ticket: "", description: "=SUM(A1)", minutes: 30, estimated: false),
                Entry(id: "x", date: "2026-11-02", ticket: "", description: "next month", minutes: 30, estimated: false),
            ]
            store.setAbsence(.vacation, on: "2026-10-27")
            let lines = store.monthCSV(containing: "2026-10-15").components(separatedBy: "\r\n").filter { !$0.isEmpty }
            #expect(lines.count == 4, "header, two entries, one day off; November is left out")
            #expect(lines[0].hasPrefix("Datum;Wochentag;Ticket"))
            #expect(lines[1] == "2026-10-02;Freitag;;;'=SUM(A1);30;0,50;nein;nein;", "formulas are defused")
            #expect(lines[2] == "2026-10-26;Montag;PROJ-1;;\"Review; Teil \"\"2\"\"\";90;1,50;ja;nein;", "separator and quotes are escaped")
            #expect(lines[3] == "2026-10-27;Dienstag;;;Urlaub;0;0,00;nein;nein;Urlaub")
        }
    }

    @Test func englishUsesCommasAndDots() {
        pinBerlin()
        withTestStore { store in
            store.appLanguage = .en
            store.database.entries = [Entry(id: "a", date: "2026-10-26", ticket: "PROJ-1", description: "Review", minutes: 45, estimated: false)]
            let csv = store.monthCSV(containing: "2026-10-26")
            #expect(csv.contains("2026-10-26,Monday,PROJ-1,,Review,45,0.75,no,no,"))
            #expect(SchichtaStore.monthBounds(of: "2026-02-10") == ("2026-02-01", "2026-02-28"))
        }
    }
}

@Suite("Book a week")
@MainActor
struct WeekBookingTests {
    /// A target on a closed local port: rendering works, sending fails fast.
    func model() throws -> WeekBookingModel {
        let target = try BookingTarget.parse(id: "local", data: Data(#"{"name":"Local","url":"http://127.0.0.1:9/book","mode":"perDay","body":{"d":"{{date}}"}}"#.utf8))
        let model = WeekBookingModel()
        model.targets = [BookingTargetsModel.Loaded(id: "local", target: target, error: nil)]
        model.targetId = "local"
        return model
    }

    @Test func onlyOpenDaysWithConfirmedEntriesAreReady() throws {
        pinBerlin()
        try withTestStore { store in
            store.database.entries = [
                Entry(id: "a", date: "2026-10-26", ticket: "PROJ-1", description: "Mon", minutes: 60, estimated: false),
                Entry(id: "b", date: "2026-10-27", ticket: "PROJ-1", description: "Tue", minutes: 60, estimated: true),
                Entry(id: "c", date: "2026-10-28", ticket: "PROJ-1", description: "Wed", minutes: 60, estimated: false),
                Entry(id: "d", date: "2026-10-30", ticket: "PROJ-1", description: "Fri, future", minutes: 60, estimated: false),
            ]
            store.database.journal["2026-10-28"] = JournalItem(booked: true)
            let model = try model()
            model.prepare(store: store, week: store.weekSummary(containing: "2026-10-26", today: "2026-10-29"), today: "2026-10-29")
            #expect(model.plans.map(\.day) == ["2026-10-26", "2026-10-27"], "booked and future days are left out")
            #expect(model.readyPlans.map(\.day) == ["2026-10-26"])
            #expect(model.plans[1].skipReason != nil, "unconfirmed estimates block the day")
        }
    }

    @Test func aFailedDayIsNotMarkedBooked() async throws {
        pinBerlin()
        let suite = "local.schichta.tests.weekBookingFailure"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("schichta-tests-\(UUID().uuidString)")
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dir)
        }
        let store = SchichtaStore(storeURL: dir.appendingPathComponent("schichta.json"), defaults: UserDefaults(suiteName: suite)!)
        store.database.entries = [Entry(id: "a", date: "2026-10-26", ticket: "PROJ-1", description: "Mon", minutes: 60, estimated: false)]
        let model = try model()
        model.prepare(store: store, week: store.weekSummary(containing: "2026-10-26", today: "2026-10-27"), today: "2026-10-27")
        model.send(store: store)
        for _ in 0..<100 where model.isSending { try await Task.sleep(for: .milliseconds(100)) }
        #expect(!model.isSending)
        #expect(model.plans.first?.sent == false)
        #expect(model.plans.first?.result?.contains("0/1") == true)
        #expect(store.database.journal["2026-10-26"]?.booked != true)
    }
}
