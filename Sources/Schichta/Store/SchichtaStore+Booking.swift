import AppKit

extension SchichtaStore {
    // --- Booking Status & Day Queries ---

    func toggleDayBooked(_ day: String? = nil) {
        let target = day ?? selectedDay
        markDayBooked(target, booked: database.journal[target]?.booked != true)
    }

    func markDayBooked(_ day: String, booked: Bool = true) {
        var item = database.journal[day] ?? JournalItem()
        item.booked = booked
        database.journal[day] = item
        save()
        if booked && hookAutoTriggerOnBook {
            runExternalHook(for: day)
        }
        showToast(booked ? t("booking.dayMarkedAsBooked", "\(SchichtaCore.formatGermanDate(day))") : t("booking.dayMarkedAsOpen", "\(SchichtaCore.formatGermanDate(day))"))
    }

    func isDayUnbooked(_ day: String) -> Bool {
        guard SchichtaCore.isValidDate(day) else { return false }
        let today = SchichtaCore.day()
        guard day <= today else { return false }
        let item = database.journal[day]
        if item?.booked == true { return false }

        return hasActivity(day) || isWorkingDay(day)
    }

    /// Has entries or non-empty daily notes.
    func hasActivity(_ day: String) -> Bool {
        database.entries.contains(where: { $0.date == day }) ||
            !(database.journal[day]?.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func previousWorkingDay(before today: String = SchichtaCore.day()) -> String {
        // Working days of the last 14 days, newest first.
        let workDays = (1...14).map { SchichtaCore.addDays(-$0, to: today) }.filter(isWorkingDay)
        let isBooked = { (day: String) in self.database.journal[day]?.booked == true }

        // 1. unbooked with entries/notes, 2. any unbooked working day, 3. last working day, 4. yesterday.
        return workDays.first(where: { !isBooked($0) && self.hasActivity($0) })
            ?? workDays.first(where: { !isBooked($0) })
            ?? workDays.first
            ?? SchichtaCore.addDays(-1, to: today)
    }

    func unbookedPreviousDay(today: String = SchichtaCore.day()) -> String? {
        let prev = previousWorkingDay(before: today)
        guard prev < today else { return nil }
        if isDayUnbooked(prev) {
            return prev
        }
        return nil
    }

    // --- Prompt Configuration & Actions ---

    var endOfDayPromptTimeString: String {
        String(format: "%02d:%02d", workEndHour, workEndMinute)
    }

    func triggerEndOfDayPromptManually() {
        let day = selectedDay
        self.activePrompt = .endOfDay(day: day)
        appDelegate()?.sendEndOfDayPromptNotification(for: day)
        appDelegate()?.bringMainWindowToFront()
        showToast(t("booking.endOfDayPromptTriggered"))
    }

    func triggerMorningPromptManually() {
        let unbooked = unbookedPreviousDay(today: selectedDay) ?? previousWorkingDay(before: selectedDay)
        self.activePrompt = .morning(unbookedDay: unbooked)
        appDelegate()?.sendMorningPromptNotification(for: unbooked)
        appDelegate()?.bringMainWindowToFront()
        showToast(t("booking.morningPromptForTriggered", "\(SchichtaCore.formatGermanDate(unbooked))"))
    }
}
