import Foundation
import Testing
@testable import Schichta

@Suite("Week overview")
@MainActor
struct WeekSummaryTests {
    /// Week 44/2026: Monday 26 Oct to Sunday 1 Nov; "today" is Wednesday 28 Oct.
    func week(_ store: SchichtaStore) -> WeekSummary {
        store.weekSummary(containing: "2026-10-29", today: "2026-10-28")
    }

    @Test func weekRunsMondayToSunday() {
        pinBerlin()
        #expect(SchichtaStore.weekStart(of: "2026-10-26") == "2026-10-26", "Monday")
        #expect(SchichtaStore.weekStart(of: "2026-11-01") == "2026-10-26", "Sunday belongs to the week before")
        #expect(SchichtaStore.weekStart(of: "2026-10-25") == "2026-10-19")
        withTestStore { store in
            let w = week(store)
            #expect(w.start == "2026-10-26" && w.end == "2026-11-01")
            #expect(w.weekNumber == 44)
        }
    }

    @Test func totalsTargetsAndBalanceSoFar() {
        pinBerlin()
        withTestStore { store in
            store.dailyTargetMinutes = 480
            store.database.entries = [
                Entry(id: "a", date: "2026-10-26", ticket: "PROJ-1", description: "Mon", minutes: 540, estimated: false),
                Entry(id: "b", date: "2026-10-27", ticket: "PROJ-2", description: "Tue", minutes: 360, estimated: true),
                Entry(id: "c", date: "2026-10-28", ticket: "PROJ-1", description: "Wed", minutes: 120, estimated: false),
                Entry(id: "x", date: "2026-11-02", ticket: "PROJ-9", description: "next week", minutes: 60, estimated: false),
            ]
            let w = week(store)
            #expect(w.total == 1020, "next week's entry is not counted")
            #expect(w.target == 5 * 480)
            #expect(w.balanceSoFar == 1020 - 3 * 480, "Thursday and Friday are still ahead")
            #expect(w.estimatedCount == 1)
            #expect(w.ticketTotals.map(\.ticket) == ["PROJ-1", "PROJ-2"])
            #expect(w.ticketTotals.first?.minutes == 660)
        }
    }

    @Test func entriesWithoutTicketAreSplitByProject() {
        withTestStore { store in
            store.database.entries = [
                Entry(id: "a", date: "2026-10-26", ticket: "", description: "Meeting", minutes: 60, estimated: false, project: "Example App"),
                Entry(id: "b", date: "2026-10-27", ticket: "", description: "Mail", minutes: 30, estimated: false, project: "Example API"),
                Entry(id: "c", date: "2026-10-27", ticket: "", description: "Sync", minutes: 30, estimated: false, project: "Example App"),
            ]
            let totals = week(store).ticketTotals
            #expect(totals == [
                TicketTotal(ticket: "", project: "Example App", minutes: 90),
                TicketTotal(ticket: "", project: "Example API", minutes: 30),
            ])
        }
    }

    @Test func unbookedPastDaysAndStatuses() {
        pinBerlin()
        withTestStore { store in
            store.database.journal["2026-10-26"] = JournalItem(booked: true)
            store.database.journal["2026-10-31"] = JournalItem(notes: "Saturday work") // future, so not yet unbooked
            let w = week(store)
            #expect(w.unbookedDays == ["2026-10-27"], "Monday is booked, Wednesday is today")
            #expect(w.bookedWorkingDays == 1 && w.workingDays == 5)
            let today = w.days.first { $0.isToday }
            #expect(today?.day == "2026-10-28")
            #expect(w.days.filter(\.isFuture).count == 4)
            #expect(w.days[5].target == 0, "Saturday has no target")
        }
    }

    @Test func weekReportListsDaysAndTickets() {
        pinBerlin()
        withTestStore { store in
            store.appLanguage = .en
            store.database.entries = [
                Entry(id: "a", date: "2026-10-26", ticket: "PROJ-1", description: "Mon", minutes: 90, estimated: false),
                Entry(id: "b", date: "2026-10-27", ticket: "", description: "Tue", minutes: 30, estimated: false),
            ]
            let report = store.weekReport(week(store))
            #expect(report.hasPrefix("Week 44: 26.10.2026 – 01.11.2026"))
            #expect(report.contains("Monday 26.10.2026: 01:30"))
            #expect(report.contains("PROJ-1: 01:30"))
            #expect(report.contains("No ticket: 00:30"))
            #expect(!report.contains("Wednesday"), "days without time are left out")
        }
    }

    @Test func openingADaySwitchesBackToTheDayView() {
        withTestStore { store in
            store.mainViewMode = .week
            store.openDay("2026-10-27")
            #expect(store.mainViewMode == .day && store.selectedDay == "2026-10-27")
            store.moveWeek(1)
            #expect(store.selectedDay == "2026-11-03")
        }
    }
}
