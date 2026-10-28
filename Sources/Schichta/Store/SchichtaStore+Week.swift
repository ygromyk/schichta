import Foundation

/// Day or week view in the main window.
enum MainViewMode: String, CaseIterable {
    case day, week
}

/// One day of the week overview.
struct DaySummary: Equatable {
    let day: String
    let minutes: Int
    /// The daily target on working days, 0 otherwise.
    let target: Int
    let estimatedCount: Int
    let booked: Bool
    let isWorkingDay: Bool
    /// Vacation, sick or holiday: no target.
    let absence: Absence?
    let isToday: Bool
    let isFuture: Bool
    /// A past day that still needs booking (working day or day with activity).
    let isUnbooked: Bool
}

/// Time booked per ticket and project over the week (entries without a ticket are split by project).
struct TicketTotal: Hashable {
    let ticket: String
    let project: String
    let minutes: Int
}

/// Monday to Sunday around one day.
struct WeekSummary: Equatable {
    let days: [DaySummary]
    let weekNumber: Int
    let ticketTotals: [TicketTotal]

    var start: String { days.first?.day ?? "" }
    var end: String { days.last?.day ?? "" }
    var total: Int { days.reduce(0) { $0 + $1.minutes } }
    var target: Int { days.reduce(0) { $0 + $1.target } }
    var estimatedCount: Int { days.reduce(0) { $0 + $1.estimatedCount } }
    var unbookedDays: [String] { days.filter(\.isUnbooked).map(\.day) }
    var bookedWorkingDays: Int { days.filter { $0.isWorkingDay && $0.booked }.count }
    var workingDays: Int { days.filter(\.isWorkingDay).count }

    /// Logged minus target, counting only days up to today: future days don't put you behind yet.
    var balanceSoFar: Int {
        days.filter { !$0.isFuture }.reduce(0) { $0 + $1.minutes - $1.target }
    }
}

extension SchichtaStore {
    /// The Monday of the week containing `day`.
    static func weekStart(of day: String) -> String {
        let weekday = AppTime.calendar.component(.weekday, from: SchichtaCore.date(fromDay: day)) // 1 = Sunday
        return SchichtaCore.addDays(-((weekday + 5) % 7), to: day)
    }

    func weekSummary(containing day: String, today: String = SchichtaCore.day()) -> WeekSummary {
        let start = Self.weekStart(of: day)
        let dayStrings = (0..<7).map { SchichtaCore.addDays($0, to: start) }
        let weekEntries = database.entries.filter { $0.date >= start && $0.date <= dayStrings[6] }

        let days = dayStrings.map { d -> DaySummary in
            let entries = weekEntries.filter { $0.date == d }
            let working = isWorkingDay(d)
            let booked = database.journal[d]?.booked == true
            return DaySummary(
                day: d,
                minutes: entries.reduce(0) { $0 + $1.minutes },
                target: working ? dailyTargetMinutes : 0,
                estimatedCount: entries.filter(\.estimated).count,
                booked: booked,
                isWorkingDay: working,
                absence: absence(on: d),
                isToday: d == today,
                isFuture: d > today,
                isUnbooked: d < today && !booked && (working || hasActivity(d))
            )
        }

        struct Key: Hashable { let ticket: String; let project: String }
        var totals: [Key: Int] = [:]
        for entry in weekEntries {
            let key = Key(ticket: entry.ticket.trimmingCharacters(in: .whitespacesAndNewlines),
                          project: SchichtaCore.resolveProjectName(for: entry, repos: trackedRepos))
            totals[key, default: 0] += entry.minutes
        }
        let ticketTotals = totals
            .map { TicketTotal(ticket: $0.key.ticket, project: $0.key.project, minutes: $0.value) }
            .sorted { ($0.minutes, $1.ticket, $1.project) > ($1.minutes, $0.ticket, $0.project) }

        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = AppTime.timeZone
        let weekNumber = iso.component(.weekOfYear, from: SchichtaCore.date(fromDay: start))
        return WeekSummary(days: days, weekNumber: weekNumber, ticketTotals: ticketTotals)
    }

    /// Plain-text week summary for pasting into a booking tool or mail.
    func weekReport(_ week: WeekSummary) -> String {
        var lines = [
            t("week.week", "\(week.weekNumber)", "\(SchichtaCore.formatGermanDate(week.start))", "\(SchichtaCore.formatGermanDate(week.end))"),
            t("week.totalOf", "\(SchichtaCore.formatTime(week.total))", "\(SchichtaCore.formatTime(week.target))"),
            "",
        ]
        for d in week.days where d.minutes > 0 {
            let name = SchichtaCore.weekdayName(d.day, language: appLanguage)
            lines.append("\(name) \(SchichtaCore.formatGermanDate(d.day)): \(SchichtaCore.formatTime(d.minutes))")
        }
        if !week.ticketTotals.isEmpty {
            lines.append("")
            lines.append(t("week.byTicket"))
            for total in week.ticketTotals {
                let ticket = total.ticket.isEmpty ? t("week.noTicket") : total.ticket
                let project = total.project.isEmpty ? "" : " (\(total.project))"
                lines.append("\(ticket)\(project): \(SchichtaCore.formatTime(total.minutes))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The first day of the overtime account: the start date from Settings, else the first entry, else today.
    func overtimeStart(today: String = SchichtaCore.day()) -> String {
        if SchichtaCore.isValidDate(overtimeStartDate) { return overtimeStartDate }
        return database.entries.map(\.date).min().map { min($0, today) } ?? today
    }

    /// Overtime account: opening balance plus, for every day from the start to today, logged minus target.
    /// Uses today's daily target for past days too, and days off (vacation, sick, holiday) have no target.
    func overtimeBalance(today: String = SchichtaCore.day()) -> Int {
        let start = overtimeStart(today: today)
        guard start <= today else { return overtimeOpeningMinutes }
        var logged: [String: Int] = [:]
        for entry in database.entries where entry.date >= start && entry.date <= today {
            logged[entry.date, default: 0] += entry.minutes
        }
        var balance = overtimeOpeningMinutes
        // Walk Date values: parsing and formatting a day string per step was the cost on every render.
        let time = AppTime.state
        guard var date = time.day.date(from: start), let end = time.day.date(from: today) else { return balance }
        var guardDays = 0
        while date <= end && guardDays < 3660 { // ten years at most
            let day = time.day.string(from: date)
            let weekday = time.calendar.component(.weekday, from: date)
            let working = workingDays.contains(weekday) && absence(on: day) == nil
            balance += logged[day, default: 0] - (working ? dailyTargetMinutes : 0)
            guard let next = time.calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
            guardDays += 1
        }
        return balance
    }

    func moveWeek(_ offset: Int) {
        selectDay(SchichtaCore.addDays(7 * offset, to: selectedDay))
    }

    /// Opens a day from the week overview in the day view.
    func openDay(_ day: String) {
        selectDay(day)
        mainViewMode = .day
    }
}
