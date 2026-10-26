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
        showToast(booked ? t("Tag \(SchichtaCore.formatGermanDate(day)) als gebucht markiert ✓", "Day \(SchichtaCore.formatGermanDate(day)) marked as booked ✓") : t("Tag \(SchichtaCore.formatGermanDate(day)) als offen markiert.", "Day \(SchichtaCore.formatGermanDate(day)) marked as open."))
    }

    func isDayUnbooked(_ day: String) -> Bool {
        guard SchichtaCore.isValidDate(day) else { return false }
        let today = SchichtaCore.day()
        guard day <= today else { return false }
        let item = database.journal[day]
        if item?.booked == true { return false }

        return hasActivity(day) || isWorkingDay(day)
    }

    /// Einträge oder nicht-leere Tagesnotizen vorhanden.
    func hasActivity(_ day: String) -> Bool {
        database.entries.contains(where: { $0.date == day }) ||
            !(database.journal[day]?.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func previousWorkingDay(before today: String = SchichtaCore.day()) -> String {
        // Arbeitstage der letzten 14 Tage, neuester zuerst.
        let workDays = (1...14).map { SchichtaCore.addDays(-$0, to: today) }.filter(isWorkingDay)
        let isBooked = { (day: String) in self.database.journal[day]?.booked == true }

        // 1. Ungebucht mit Einträgen/Notizen, 2. irgendein ungebuchter Arbeitstag, 3. letzter Arbeitstag, 4. gestern.
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
        showToast(t("Feierabend-Prompt ausgelöst.", "End-of-day prompt triggered."))
    }

    func triggerMorningPromptManually() {
        let unbooked = unbookedPreviousDay(today: selectedDay) ?? previousWorkingDay(before: selectedDay)
        self.activePrompt = .morning(unbookedDay: unbooked)
        appDelegate()?.sendMorningPromptNotification(for: unbooked)
        appDelegate()?.bringMainWindowToFront()
        showToast(t("Morgen-Prompt für \(SchichtaCore.formatGermanDate(unbooked)) ausgelöst.", "Morning prompt for \(SchichtaCore.formatGermanDate(unbooked)) triggered."))
    }
}
