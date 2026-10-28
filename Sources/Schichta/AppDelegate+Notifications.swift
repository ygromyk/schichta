import Cocoa
import UserNotifications

extension AppDelegate {
    func playCheckInSound(customName: String? = nil) {
        guard (store?.checkInSoundEnabled == true) || customName != nil else { return }
        let soundName = customName ?? store?.checkInSoundName ?? "Glass"
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.play()
        } else if let fallback = NSSound(named: NSSound.Name("Glass")) {
            fallback.play()
        }
    }

    @discardableResult
    static func ensureNotificationIconSaved() -> URL {
        if !FileManager.default.fileExists(atPath: notificationIconURL.path) {
            try? AppIconGenerator.pngData(AppIconGenerator.makeIcon(size: 256))?.write(to: notificationIconURL)
        }
        return notificationIconURL
    }

    static func makeNotificationContent(title: String, subtitle: String = "", body: String, soundEnabled: Bool = true) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        if !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.body = body
        if soundEnabled {
            content.sound = .default
        }

        let persistentIconURL = ensureNotificationIconSaved()
        if FileManager.default.fileExists(atPath: persistentIconURL.path) {
            let tempIconURL = FileManager.default.temporaryDirectory.appendingPathComponent("zb-notif-\(UUID().uuidString).png")
            do {
                try FileManager.default.copyItem(at: persistentIconURL, to: tempIconURL)
                let attachment = try UNNotificationAttachment(identifier: "schichta-icon", url: tempIconURL, options: nil)
                content.attachments = [attachment]
            } catch {
                NSLog("Could not create the notification attachment: %@", error.localizedDescription)
            }
        }
        return content
    }

    func makeNotificationContent(title: String, subtitle: String = "", body: String) -> UNMutableNotificationContent {
        AppDelegate.makeNotificationContent(
            title: title,
            subtitle: subtitle,
            body: body,
            soundEnabled: store?.checkInSoundEnabled ?? true
        )
    }

    nonisolated static func checkInWindowString(for date: Date = Date(), intervalMinutes: Int = 30, language: AppLanguage = .de) -> String {
        let start = date.addingTimeInterval(-Double(intervalMinutes * 60))
        let suffix = L10n.string("app.minuteCheckIn", ["\(intervalMinutes)"], language: language)
        return "\(AppTime.clock.string(from: start)) – \(AppTime.clock.string(from: date)) · \(suffix)"
    }

    nonisolated static func checkInCurrentTimeString(for date: Date = Date()) -> String {
        AppTime.clock.string(from: date)
    }

    /// Notifications only in the bundled app; a bare binary or the test run has no notification center.
    private var notificationsAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func setupNotificationCenter() {
        guard notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // @Sendable keeps the callback off the main actor: it runs on a UserNotifications queue, and with SDKs
        // before macOS 26 a closure written here would inherit main-actor isolation and trap at that check.
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshNotificationAuthorization() }
        }
        registerNotificationCategories()
    }

    /// Mirrors the system permission into the store, so Settings can say when notifications are turned off.
    func refreshNotificationAuthorization() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().getNotificationSettings { @Sendable [weak self] settings in
            let denied = settings.authorizationStatus == .denied
            DispatchQueue.main.async { self?.store?.notificationsDenied = denied }
        }
    }

    /// The Notifications pane of System Settings, where the permission is switched back on.
    func openNotificationSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Check-in notifications can be answered in place: a reply field, "same as before" and "later".
    /// Morning and end-of-day notifications can be put off with "ask later".
    func registerNotificationCategories() {
        guard notificationsAvailable else { return }
        let reply = UNTextInputNotificationAction(
            identifier: "reply",
            title: t("notification.reply"),
            options: [],
            textInputButtonTitle: t("notification.save"),
            textInputPlaceholder: t("notification.replyPlaceholder"))
        let same = UNNotificationAction(identifier: "same", title: t("notification.sameAsBefore"), options: [])
        let later = UNNotificationAction(identifier: "later", title: t("notification.later"), options: [])
        let askLater = UNNotificationAction(identifier: "askLater", title: t("notification.askLater"), options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: AppDelegate.checkInCategory, actions: [reply, same, later], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: AppDelegate.dayPromptCategory, actions: [askLater], intentIdentifiers: [], options: []),
        ])
    }

    /// Posting with an `id` already in Notification Center replaces that notification instead of adding a second one.
    /// An `id` prefixed "morning-prompt"/"endofday-prompt" opens the main window on click, anything else the check-in.
    private func postNotification(id: String, category: String? = nil, title: String, body: String) {
        guard notificationsAvailable else { return }
        let content = makeNotificationContent(title: title, body: body)
        if let category { content.categoryIdentifier = category }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { @Sendable error in
            if let error { NSLog("Could not post notification %@: %@", id, error.localizedDescription) }
        }
    }

    private func removeNotifications(ids: [String]) {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    func sendCheckInNotification() {
        if case .beforeLunch = store.checkInRequest.reason {
            postNotification(id: AppDelegate.checkInNotificationID, category: AppDelegate.checkInCategory,
                             title: t("notification.lunch.title"), body: t("notification.lunch.body"))
            return
        }
        let minutes = store.reminderIntervalMinutes
        postNotification(id: AppDelegate.checkInNotificationID, category: AppDelegate.checkInCategory,
                         title: t("notification.checkIn.title", "\(minutes)"), body: t("notification.checkIn.body"))
    }

    /// The check-in was answered or dismissed: its notification has nothing left to ask.
    func removeCheckInNotification() {
        removeNotifications(ids: [AppDelegate.checkInNotificationID])
    }

    static func dayPromptNotificationID(for prompt: ActivePrompt) -> String? {
        switch prompt {
        case .none: nil
        case .morning(let unbookedDay): morningPromptIDPrefix + unbookedDay
        case .endOfDay(let day): endOfDayPromptIDPrefix + day
        }
    }

    /// The banner in the main window was answered or closed: take its notification along.
    func removeDayPromptNotification(for prompt: ActivePrompt) {
        guard let id = AppDelegate.dayPromptNotificationID(for: prompt) else { return }
        removeNotifications(ids: [id])
    }

    /// True when what the notification asks for is already on screen: the main window with its banner for a
    /// day prompt, or the check-in panel with the keyboard. A banner on top would only repeat it.
    func isPromptOnScreen(category: String) -> Bool {
        switch category {
        case AppDelegate.dayPromptCategory:
            return NSApp.isActive && window?.isKeyWindow == true
        case AppDelegate.checkInCategory:
            return checkInPanel?.isKeyWindow == true
        default:
            return false
        }
    }

    // UNUserNotificationCenterDelegate
    // The notification center may call these on any thread.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let category = notification.request.content.categoryIdentifier
        let onScreen = await MainActor.run { self.isPromptOnScreen(category: category) }
        return onScreen ? [] : [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        let action = response.actionIdentifier
        let reply = (response as? UNTextInputNotificationResponse)?.userText
        DispatchQueue.main.async { [weak self] in
            self?.handleNotificationResponse(id: id, action: action, reply: reply)
        }
        completionHandler()
    }

    func handleNotificationResponse(id: String, action: String, reply: String?) {
        switch action {
        case "reply":
            guard let reply, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            store.checkInFromReply(reply)
            checkInAnswered()
            closeCheckInPanel()
        case "same":
            if store.repeatLastCheckIn(minutes: store.prefilledMinutes(for: store.checkInRequest.reason)) {
                checkInAnswered()
                closeCheckInPanel()
            } else {
                showCheckInPanel()
            }
        case "later":
            snoozeCheckIn()
        case "askLater":
            snoozeDayPrompt(id: id)
        default:
            if id.hasPrefix(AppDelegate.morningPromptIDPrefix) || id.hasPrefix(AppDelegate.endOfDayPromptIDPrefix) {
                bringMainWindowToFront()
            } else {
                showCheckInPanel(anchorButton: nil)
            }
        }
    }

    func sendMorningPromptNotification(for unbookedDay: String) {
        let dateStr = SchichtaCore.formatFullDate(unbookedDay, language: store?.appLanguage ?? .de)
        postNotification(id: AppDelegate.morningPromptIDPrefix + unbookedDay, category: AppDelegate.dayPromptCategory,
                         title: t("notification.morning.title"), body: t("notification.morning.body", dateStr))
    }

    func sendEndOfDayPromptNotification(for day: String) {
        let dateStr = SchichtaCore.formatFullDate(day, language: store?.appLanguage ?? .de)
        postNotification(id: AppDelegate.endOfDayPromptIDPrefix + day, category: AppDelegate.dayPromptCategory,
                         title: t("notification.endOfDay.title"), body: t("notification.endOfDay.body", dateStr))
    }
}
