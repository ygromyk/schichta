import Foundation

/// Why the check-in panel is open: sets its headline, the pre-filled duration and extra buttons.
enum CheckInReason: Equatable {
    /// ⌘K, the global shortcut, the menu bar or a notification click.
    case manual
    /// The regular interval timer.
    case timer
    /// Shortly before lunch: asks for the morning, with the time since the last check-in.
    case beforeLunch
    /// Back after an away period (idle, sleep or locked screen).
    case back(AwayPeriod)
}

/// One opening of the check-in panel. A new `id` resets the panel's fields.
struct CheckInRequest: Equatable {
    let id = UUID()
    let reason: CheckInReason
}

/// Time away from the Mac.
struct AwayPeriod: Equatable {
    let from: Date
    let to: Date
    var minutes: Int { Int((to.timeIntervalSince(from) / 60).rounded()) }
}

/// Tracks time away from the Mac. Fed with idle times and sleep/lock events; reports an away period
/// once the user is back, if it lasted at least `minimumAway`.
struct AwayTracker {
    var minimumAway: TimeInterval
    /// Longer absences (nights, weekends) are not asked about.
    var maximumAway: TimeInterval = 5 * 60 * 60
    private(set) var awaySince: Date?

    init(minimumAway: TimeInterval) {
        self.minimumAway = minimumAway
    }

    var isAway: Bool { awaySince != nil }

    /// Sleep or screen lock: away from now on (an earlier start from idle time is kept).
    mutating func wentAway(at date: Date) {
        if awaySince == nil { awaySince = date }
    }

    /// Called regularly with the seconds since the last keyboard/mouse input.
    mutating func update(now: Date, idleSeconds: TimeInterval) -> AwayPeriod? {
        if idleSeconds >= minimumAway {
            wentAway(at: now.addingTimeInterval(-idleSeconds))
            return nil
        }
        // Input again: the user came back with their first input.
        return cameBack(at: now.addingTimeInterval(-idleSeconds))
    }

    /// Screen unlocked or input seen again.
    mutating func cameBack(at date: Date) -> AwayPeriod? {
        guard let start = awaySince else { return nil }
        awaySince = nil
        let length = date.timeIntervalSince(start)
        guard length >= minimumAway, length <= maximumAway else { return nil }
        return AwayPeriod(from: start, to: date)
    }
}

extension SchichtaStore {
    /// Opens the check-in panel for `reason` (the AppDelegate shows it; tests only see the request).
    func requestCheckIn(_ reason: CheckInReason) {
        checkInRequest = CheckInRequest(reason: reason)
    }

    /// The duration the panel starts with.
    func prefilledMinutes(for reason: CheckInReason, now: Date = Date()) -> Int {
        switch reason {
        case .manual, .timer:
            return snapDuration(reminderIntervalMinutes)
        case .beforeLunch:
            return snapDuration(minutesSinceLastCheckIn(now: now) ?? reminderIntervalMinutes)
        case .back(let period):
            return snapDuration(period.minutes)
        }
    }

    /// Minutes since today's last check-in, or since the start of work if there was none yet.
    func minutesSinceLastCheckIn(now: Date = Date()) -> Int? {
        let today = SchichtaCore.day(from: now)
        let lastTime = (database.journal[today]?.notes ?? "")
            .components(separatedBy: .newlines)
            .compactMap(Self.checkInClock)
            .last
        let (hour, minute) = lastTime ?? (workStartHour, workStartMinute)
        guard let since = AppTime.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now), since < now else { return nil }
        return min(1440, Int(now.timeIntervalSince(since) / 60))
    }

    /// Hour and minute of a check-in note line ("- 09:30 (30 Min.): …").
    private static func checkInClock(_ line: String) -> (Int, Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        guard AutoSynthesizer.checkInRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) != nil,
              let match = trimmed.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) else { return nil }
        let parts = trimmed[match].split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    /// The most recent check-in (ticket and text) from the last two weeks of notes.
    func lastCheckIn(before now: Date = Date()) -> (ticket: String, text: String)? {
        let today = SchichtaCore.day(from: now)
        let days = database.journal.keys.filter { $0 <= today }.sorted(by: >).prefix(14)
        for day in days {
            let lines = (database.journal[day]?.notes ?? "").components(separatedBy: .newlines).reversed()
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let ns = trimmed as NSString
                guard let m = AutoSynthesizer.checkInRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
                      m.range(at: 3).location != NSNotFound else { continue }
                let text = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                let ticket = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
                return (ticket, text)
            }
        }
        return nil
    }

    /// Logs the last check-in again with `minutes`.
    @discardableResult
    func repeatLastCheckIn(minutes: Int, mode: CheckInMode? = nil, now: Date = Date()) -> Bool {
        guard let last = lastCheckIn(before: now) else { return false }
        handleCheckIn(text: last.text, ticket: last.ticket, mode: mode ?? defaultCheckInMode,
                      timeStr: AppTime.clock.string(from: now), minutes: minutes)
        return true
    }

    /// A check-in typed into a notification: a ticket anywhere in the text is used as the ticket.
    func checkInFromReply(_ reply: String, now: Date = Date()) {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let ticket = AutoSynthesizer.extractTicket(from: text) ?? ""
        if !ticket.isEmpty {
            // "PROJ-1 fix login" / "[PROJ-1]: fix login": a leading ticket goes into the ticket field only.
            text = text.replacingOccurrences(of: #"^\[?[A-Za-z][A-Za-z0-9]+-\d+\]?[:\s-]*"#, with: "", options: .regularExpression)
        }
        handleCheckIn(text: text.isEmpty ? reply : text, ticket: ticket, mode: defaultCheckInMode,
                      timeStr: AppTime.clock.string(from: now), minutes: prefilledMinutes(for: checkInRequest.reason, now: now))
    }

    /// Notes an away period as a break, so the day's notes show the gap; nothing is booked.
    func logBreak(_ period: AwayPeriod) {
        let day = SchichtaCore.day(from: period.to)
        let line = "- \(AppTime.clock.string(from: period.from))–\(AppTime.clock.string(from: period.to)) \(t("Pause", "Break"))"
        var item = database.journal[day] ?? JournalItem()
        let base = item.notes.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        item.notes = base.isEmpty ? line : "\(base)\n\(line)"
        database.journal[day] = item
        save()
        showToast(t("Pause notiert (\(SchichtaCore.formatTime(period.minutes))).", "Break noted (\(SchichtaCore.formatTime(period.minutes)))."))
    }

    /// True once a working day reaches the lunch time, for 90 minutes, unless already asked today.
    func isLunchPromptDue(now: Date = Date()) -> Bool {
        let today = SchichtaCore.day(from: now)
        guard lunchPromptEnabled, isWorkingDay(today), lastLunchPromptDate != today else { return false }
        let time = AppTime.calendar.dateComponents([.hour, .minute], from: now)
        let current = (time.hour ?? 0) * 60 + (time.minute ?? 0)
        let lunch = lunchHour * 60 + lunchMinute
        return current >= lunch && current < lunch + 90
    }

    /// Whether an away period should be asked about: it touches the working hours of a working day.
    func shouldAskAbout(_ period: AwayPeriod) -> Bool {
        awayDetectionEnabled && (isCurrentlyWithinWorkingHours(period.from) || isCurrentlyWithinWorkingHours(period.to))
    }
}
