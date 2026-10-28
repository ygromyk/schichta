import Cocoa

extension AppDelegate {
    // MARK: - Escalation: quiet panel first, a notification only if it stays unanswered

    func scheduleEscalation() {
        cancelEscalation()
        escalationTask = Task { [weak self] in
            try? await Task.sleep(for: AppDelegate.escalationDelay)
            guard !Task.isCancelled, let self, self.isCheckInDue, !self.isAway else { return }
            self.sendCheckInNotification()
        }
    }

    func cancelEscalation() {
        escalationTask?.cancel()
        escalationTask = nil
    }

    func startCheckInTimer() {
        checkInTimer?.invalidate()
        guard let store = store, store.timerEnabled else { return }
        let interval = TimeInterval(max(5, store.reminderIntervalMinutes) * 60)
        // Scheduled timers fire on the main run loop.
        checkInTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.triggerCheckInPrompt() }
        }
    }

    func snoozeCheckIn() {
        checkInAnswered()
        closeCheckInPanel()
        if store.timerEnabled {
            startCheckInTimer()
        }
    }

    /// Asks again after `dayPromptSnoozeDelay`, unless the day has been booked by then.
    func snoozeDayPrompt(id: String) {
        Task { [weak self] in
            try? await Task.sleep(for: AppDelegate.dayPromptSnoozeDelay)
            guard let self, let store = self.store else { return }
            let morning = AppDelegate.morningPromptIDPrefix, endOfDay = AppDelegate.endOfDayPromptIDPrefix
            if id.hasPrefix(morning) {
                let day = String(id.dropFirst(morning.count))
                guard store.database.journal[day]?.booked != true else { return }
                self.triggerMorningPrompt(unbookedDay: day)
            } else if id.hasPrefix(endOfDay) {
                let day = String(id.dropFirst(endOfDay.count))
                guard store.database.journal[day]?.booked != true else { return }
                self.triggerEndOfDayPrompt(day: day)
            }
        }
    }

    @objc func triggerCheckInPrompt() {
        guard let store = store, store.timerEnabled else { return }
        guard store.isCurrentlyWithinWorkingHours(), !isAway else { return }
        promptQuietly(.timer)
    }

    /// Timer and lunch prompts: the panel floats in front without taking the keyboard, with the sound;
    /// a notification follows only if nobody answers within `escalationDelay`.
    func promptQuietly(_ reason: CheckInReason) {
        isCheckInDue = true
        updateStatusItem(isDue: true)
        presentCheckIn(reason, activate: false)
        playCheckInSound()
        scheduleEscalation()
    }

    // MARK: - Day-closing prompts (morning & end of day)

    func startPromptTimer() {
        promptTimer?.invalidate()
        // Check once directly 2 seconds after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkPeriodicPrompts()
        }
        // Background timer every 60 seconds
        promptTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPeriodicPrompts() }
        }
    }

    /// `now` is injectable for tests.
    func checkPeriodicPrompts(now: Date = Date()) {
        // Once a minute: the menu bar time follows the date roll-over.
        refreshStatusItem()
        guard let store = store else { return }
        let today = SchichtaCore.day(from: now)
        let time = AppTime.calendar.dateComponents([.hour, .minute], from: now)
        let currentHour = time.hour!
        let currentTotalMinutes = currentHour * 60 + time.minute!

        // Prompt A: morning prompt (previous day not booked yet)
        if store.morningPromptEnabled && store.isWorkingDay(today) && currentHour >= store.morningPromptHour && store.lastMorningPromptDate != today {
            if let unbookedPrev = store.unbookedPreviousDay(today: today) {
                store.lastMorningPromptDate = today
                triggerMorningPrompt(unbookedDay: unbookedPrev)
                return
            }
        }

        // Lunch: ask for the morning before leaving; the next regular check-in comes a full interval later.
        if store.isLunchPromptDue(now: now) && !isAway {
            store.lastLunchPromptDate = today
            promptQuietly(.beforeLunch)
            startCheckInTimer()
            return
        }

        // Prompt B: end-of-day sign-off
        let targetEndMinutes = store.workEndHour * 60 + store.workEndMinute
        if store.endOfDayPromptEnabled && store.isWorkingDay(today) && currentTotalMinutes >= targetEndMinutes && store.lastEndOfDayPromptDate != today {
            let isTodayBooked = store.database.journal[today]?.booked == true
            if !isTodayBooked {
                store.lastEndOfDayPromptDate = today
                triggerEndOfDayPrompt(day: today)
            }
        }
    }

    func triggerMorningPrompt(unbookedDay: String) {
        bringMainWindowToFront()
        store.activePrompt = .morning(unbookedDay: unbookedDay)
        playCheckInSound()
        sendMorningPromptNotification(for: unbookedDay)
    }

    func triggerEndOfDayPrompt(day: String) {
        bringMainWindowToFront()
        store.activePrompt = .endOfDay(day: day)
        playCheckInSound()
        sendEndOfDayPromptNotification(for: day)
    }
}
