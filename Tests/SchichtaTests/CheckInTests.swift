import Foundation
import Testing
@testable import Schichta

/// 26 Oct 2026 (a Monday) at `hour:minute`, Berlin time.
private func monday(_ hour: Int, _ minute: Int = 0) -> Date {
    pinBerlin()
    return AppTime.calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: hour, minute: minute))!
}

@Suite("Away detection")
struct AwayTrackerTests {
    @Test func idleThenInputReportsTheGap() throws {
        var tracker = AwayTracker(minimumAway: 10 * 60)
        let first = tracker.update(now: monday(12, 20), idleSeconds: 15 * 60)
        #expect(first == nil, "still away")
        #expect(tracker.isAway)
        let back = tracker.update(now: monday(13, 10), idleSeconds: 5)
        let period = try #require(back)
        #expect(period.from == monday(12, 5), "away since the last input")
        #expect(period.minutes == 65)
        #expect(!tracker.isAway)
    }

    @Test func shortPausesAndNightsAreIgnored() {
        var tracker = AwayTracker(minimumAway: 10 * 60)
        tracker.wentAway(at: monday(10, 0))
        let short = tracker.cameBack(at: monday(10, 4))
        #expect(short == nil, "4 minutes is not away")

        tracker.wentAway(at: monday(8, 0))
        let night = tracker.cameBack(at: monday(16, 0))
        #expect(night == nil, "longer than five hours: not asked")
    }

    @Test func sleepKeepsTheEarlierIdleStart() throws {
        var tracker = AwayTracker(minimumAway: 10 * 60)
        _ = tracker.update(now: monday(12, 15), idleSeconds: 10 * 60)
        tracker.wentAway(at: monday(12, 20)) // lid closed later
        let back = tracker.cameBack(at: monday(13, 0))
        let period = try #require(back)
        #expect(period.from == monday(12, 5))
    }
}

@Suite("Check-in prompts")
@MainActor
struct CheckInPromptTests {
    let notes = "- 09:30 (30 Min.): [PROJ-2800] Replay testen\n- 10:45 (15 Min.): Code review"

    @Test func sameAsBeforeUsesTheLatestCheckIn() throws {
        try withTestStore { store in
            store.database.journal["2026-10-23"] = JournalItem(notes: "- 16:00 (30 Min.): [PROJ-1] Friday work")
            #expect(store.lastCheckIn(before: monday(9))?.text == "Friday work", "falls back to earlier days")

            store.database.journal["2026-10-26"] = JournalItem(notes: notes)
            let last = try #require(store.lastCheckIn(before: monday(11)))
            #expect(last.text == "Code review" && last.ticket == "")
        }
    }

    @Test func lunchAsksForTheTimeSinceTheLastCheckIn() {
        withTestStore { store in
            store.workStartHour = 9
            store.workStartMinute = 0
            #expect(store.minutesSinceLastCheckIn(now: monday(12)) == 180, "no check-in yet: since the start of work")
            store.database.journal["2026-10-26"] = JournalItem(notes: notes)
            #expect(store.minutesSinceLastCheckIn(now: monday(12)) == 75, "since 10:45")
            #expect(store.prefilledMinutes(for: .beforeLunch, now: monday(12)) == 75)
        }
    }

    @Test func lunchPromptOncePerWorkingDayInItsWindow() {
        withTestStore { store in
            store.lunchHour = 12
            store.lunchMinute = 0
            #expect(!store.isLunchPromptDue(now: monday(11, 59)))
            #expect(store.isLunchPromptDue(now: monday(12, 0)))
            #expect(!store.isLunchPromptDue(now: monday(13, 30)), "missed by more than 90 minutes: skipped")
            store.lastLunchPromptDate = "2026-10-26"
            #expect(!store.isLunchPromptDue(now: monday(12, 5)), "once per day")
            store.lunchPromptEnabled = false
            store.lastLunchPromptDate = ""
            #expect(!store.isLunchPromptDue(now: monday(12, 5)))
        }
    }

    @Test func breaksAreNotedButNeverProposed() throws {
        try withTestStore { store in
            store.appLanguage = .de
            let period = AwayPeriod(from: monday(12, 5), to: monday(13, 10))
            store.logBreak(period)
            let notes = try #require(store.database.journal["2026-10-26"]?.notes)
            #expect(notes == "- 12:05–13:10 Pause")
            #expect(store.prefilledMinutes(for: .back(period)) == 60, "65 minutes away, rounded to the 15-minute step")

            let proposals = AutoSynthesizer.synthesizeDay(
                day: "2026-10-26", journal: JournalItem(notes: notes),
                gitResult: GitActivityResult(date: "2026-10-26", timezone: "Europe/Berlin", repositories: []), existingEntries: [])
            #expect(proposals.isEmpty, "a break is not work")
        }
    }

    @Test func notificationReplyTakesTheTicketFromTheText() throws {
        try withTestStore { store in
            store.selectDay("2026-10-26")
            store.defaultCheckInMode = .both
            store.requestCheckIn(.timer)
            store.checkInFromReply("PROJ-42: fix login redirect", now: monday(10))
            let entry = try #require(store.database.entries.last)
            #expect(entry.ticket == "PROJ-42")
            #expect(entry.description == "fix login redirect")
            #expect(entry.minutes == store.reminderIntervalMinutes)
            #expect(entry.estimated)
        }
    }

    @Test func repeatingTheLastCheckInLogsItAgain() {
        withTestStore { store in
            store.defaultCheckInMode = .noteOnly
            #expect(!store.repeatLastCheckIn(minutes: 15, now: monday(11)), "nothing to repeat yet")
            store.database.journal[SchichtaCore.day()] = JournalItem(notes: "- 09:30 (30 Min.): [PROJ-2800] Replay testen")
            #expect(store.repeatLastCheckIn(minutes: 15))
            #expect(store.database.journal[SchichtaCore.day()]?.notes.hasSuffix("(15 Min.): [PROJ-2800] Replay testen") == true)
        }
    }
}

@Suite("Lunch prompt, end to end")
@MainActor
struct LunchPromptFlowTests {
    /// Runs the app's minute check at `times` with a quiet test store; returns the store and delegate.
    func run(_ times: [Date], configure: (SchichtaStore, AppDelegate) -> Void = { _, _ in },
             check: (SchichtaStore, AppDelegate) -> Void) {
        withTestStore { store in
            store.checkInSoundEnabled = false
            store.awayDetectionEnabled = false // the test machine's real idle time must not matter
            store.morningPromptEnabled = false // otherwise it fires first: an empty past working day counts as unbooked
            let delegate = AppDelegate()
            delegate.store = store
            configure(store, delegate)
            for time in times { delegate.checkPeriodicPrompts(now: time) }
            check(store, delegate)
            delegate.checkInTimer?.invalidate()
            delegate.cancelEscalation()
        }
    }

    @Test func opensTheLunchCheckInOnceAtLunchTime() {
        run([monday(11, 59)]) { store, delegate in
            #expect(store.checkInRequest.reason == .manual, "not yet")
            #expect(!delegate.isCheckInDue)
        }
        run([monday(12, 0)]) { store, delegate in
            #expect(store.checkInRequest.reason == .beforeLunch)
            #expect(store.lastLunchPromptDate == "2026-10-26")
            #expect(delegate.isCheckInDue, "menu bar shows it as due")
            #expect(delegate.escalationTask != nil, "a notification follows if unanswered")
            #expect(delegate.checkInTimer != nil, "regular interval restarts after lunch")
        }
    }

    @Test func laterTicksTheSameDayDoNotAskAgain() {
        run([monday(12, 0)]) { store, delegate in
            store.requestCheckIn(.timer) // answered, then a regular check-in came
            delegate.checkPeriodicPrompts(now: monday(12, 1))
            delegate.checkPeriodicPrompts(now: monday(12, 30))
            #expect(store.checkInRequest.reason == .timer, "lunch is asked once per day")
        }
    }

    @Test func skippedWhileAwayOrOnWeekends() {
        run([monday(12, 0)], configure: { store, delegate in
            store.awayDetectionEnabled = true
            delegate.awayTracker.wentAway(at: monday(11, 40)) // already left for lunch
        }) { store, _ in
            #expect(store.checkInRequest.reason == .manual)
            #expect(store.lastLunchPromptDate == "", "still pending if you come back within the window")
        }
        let saturday = AppTime.calendar.date(byAdding: .day, value: -2, to: monday(12, 0))!
        run([saturday]) { store, _ in
            #expect(store.checkInRequest.reason == .manual)
        }
    }

    @Test func morningPromptOnTheSameTickDelaysLunchByOneTick() {
        run([monday(12, 0)], configure: { store, _ in
            store.database.journal["2026-10-23"] = JournalItem(notes: "Friday, not booked")
            store.morningPromptEnabled = true
        }) { store, _ in
            #expect(store.activePrompt == .morning(unbookedDay: "2026-10-23"))
            #expect(store.checkInRequest.reason == .manual, "lunch waits for the next minute")
        }
        run([monday(12, 0), monday(12, 1)], configure: { store, _ in
            store.database.journal["2026-10-23"] = JournalItem(notes: "Friday, not booked")
            store.morningPromptEnabled = true
        }) { store, _ in
            #expect(store.checkInRequest.reason == .beforeLunch)
        }
    }
}

