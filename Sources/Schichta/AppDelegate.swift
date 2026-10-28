import Cocoa
import SwiftUI
import UserNotifications

// MARK: - AppDelegate & Statusbar Popover

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: NSWindow!
    var store: SchichtaStore!

    var statusItem: NSStatusItem?
    var checkInPanel: CheckInPanel?
    var settingsWindow: NSWindow?
    var checkInTimer: Timer?
    var promptTimer: Timer?
    var awayTimer: Timer?
    var isCheckInDue: Bool = false
    /// Pending notification for an unanswered check-in.
    var escalationTask: Task<Void, Never>?
    var awayTracker = AwayTracker(minimumAway: 10 * 60)
    var hotKey: GlobalHotKey?

    /// An unanswered check-in panel gets a notification after this long.
    static let escalationDelay: Duration = .seconds(3 * 60)
    static let checkInCategory = "schichta.checkin"
    static let dayPromptCategory = "schichta.dayprompt"
    /// "Ask later" on a morning or end-of-day notification asks again after this long.
    static let dayPromptSnoozeDelay: Duration = .seconds(60 * 60)

    static func activeScreen() -> NSScreen {
        let mouseLoc = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    static func centerWindow(_ win: NSWindow, on screen: NSScreen) {
        let vFrame = screen.visibleFrame
        let x = vFrame.midX - (win.frame.width / 2)
        let y = vFrame.midY - (win.frame.height / 2)
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func playCheckInSound(customName: String? = nil) {
        guard (store?.checkInSoundEnabled == true) || customName != nil else { return }
        let soundName = customName ?? store?.checkInSoundName ?? "Glass"
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.play()
        } else if let fallback = NSSound(named: NSSound.Name("Glass")) {
            fallback.play()
        }
    }

    static let notificationIconURL = AppPaths.support.appendingPathComponent("notification-icon.png")

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

    func applicationWillTerminate(_ notification: Notification) {
        store?.flushPendingSave()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply the saved time zone before the store computes "today".
        AppTime.use(AppTime.zone(forIdentifier: AppPaths.defaults.string(forKey: SchichtaStore.timeZoneKey) ?? ""))
        self.store = SchichtaStore()
        AppLanguage.current = store.appLanguage
        applyDockVisibility()

        // Set high-res native macOS app icon in Dock and Cmd+Tab switcher
        NSApp.applicationIconImage = AppIconGenerator.makeIcon(size: 512)

        // Native SwiftUI MainWindow
        let mainView = MainWindowView(store: store)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Schichta"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 950, height: 650)
        window.contentView = NSHostingView(rootView: mainView)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Schichta.MainWindow")
        AppDelegate.centerWindow(window, on: AppDelegate.activeScreen())
        window.makeKeyAndOrderFront(nil)

        setupStatusItem()
        setupCheckInPanel()
        setupNotificationCenter()
        _ = AppDelegate.ensureNotificationIconSaved()
        startCheckInTimer()
        startPromptTimer()
        startAwayDetection()
        updateGlobalHotKey()
        setupMainMenu()

        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettingsWindow() {
        showSettings(tab: store?.settingsSelectedTab ?? .general)
    }

    func showSettings(tab: SettingsTab) {
        store?.settingsSelectedTab = tab
        let targetScreen = AppDelegate.activeScreen()
        if let win = settingsWindow {
            win.title = t("app.settingsTitle")
            if !win.isVisible || win.screen != targetScreen {
                AppDelegate.centerWindow(win, on: targetScreen)
            }
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let store = store else { return }
        let settingsView = SettingsView(store: store)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.minSize = NSSize(width: 720, height: 620)
        win.title = t("app.settingsTitle")
        win.contentView = NSHostingView(rootView: settingsView)
        win.isReleasedWhenClosed = false
        AppDelegate.centerWindow(win, on: targetScreen)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = win
    }

    func updateMenuLanguage() {
        setupMainMenu()
        registerNotificationCategories()
        if let win = settingsWindow {
            win.title = t("app.settingsTitle")
        }
    }

    private func setupMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu

        appMenu.addItem(withTitle: t("app.menu.about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: t("app.menu.settings"), action: #selector(openSettingsWindow), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: t("app.menu.openCheckIn"), action: #selector(openCheckInFromMenu), keyEquivalent: "k")
        appMenu.addItem(withTitle: t("app.menu.showMainWindow"), action: #selector(showMainWindow(_:)), keyEquivalent: "0")
        #if DEBUG
        // Development only: release builds (swift build -c release) leave these out.
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: t("app.menu.testMorningPrompt"), action: #selector(testMorningPromptFromMenu), keyEquivalent: "")
        appMenu.addItem(withTitle: t("app.menu.testEndOfDayPrompt"), action: #selector(testEndOfDayPromptFromMenu), keyEquivalent: "")
        #endif
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: t("app.menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let goItem = NSMenuItem(); menu.addItem(goItem)
        let goMenu = NSMenu(title: t("app.menu.go")); goItem.submenu = goMenu
        let leftArrow = String(utf16CodeUnits: [unichar(NSLeftArrowFunctionKey)], count: 1)
        let rightArrow = String(utf16CodeUnits: [unichar(NSRightArrowFunctionKey)], count: 1)
        let goActions: [(String, Selector, String)?] = [
            ("app.menu.previous", #selector(goPrevious), leftArrow),
            ("app.menu.next", #selector(goNext), rightArrow),
            ("app.menu.today", #selector(goToday), "t"),
            nil,
            ("app.menu.dayView", #selector(goDayView), "1"),
            ("app.menu.weekView", #selector(goWeekView), "2")
        ]
        for action in goActions {
            guard let (titleKey, selector, key) = action else {
                goMenu.addItem(NSMenuItem.separator())
                continue
            }
            let item = NSMenuItem(title: t(titleKey), action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command, .option]
            item.target = self
            goMenu.addItem(item)
        }

        let editItem = NSMenuItem(); menu.addItem(editItem)
        let editMenu = NSMenu(title: t("app.menu.edit")); editItem.submenu = editMenu
        let editActions: [(String, String, String)] = [
            ("app.menu.undo", "undo:", "z"),
            ("app.menu.cut", "cut:", "x"),
            ("app.menu.copy", "copy:", "c"),
            ("app.menu.paste", "paste:", "v"),
            ("app.menu.selectAll", "selectAll:", "a")
        ]
        for (titleKey, selector, key) in editActions {
            editMenu.addItem(withTitle: t(titleKey), action: Selector(selector), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        updateStatusItem(isDue: false)
    }

    func updateStatusItem(isDue: Bool) {
        guard let button = statusItem?.button else { return }
        let label = isDue ? t("app.checkInDue") : "Schichta"
        let image = AppIconGenerator.statusBarIcon(due: isDue)
        image.accessibilityDescription = label
        button.image = image
        if let store, store.showTodayInMenuBar {
            button.title = " " + SchichtaCore.formatShortTime(store.todayMinutes())
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
        }
        button.toolTip = label
    }

    /// Redraws the menu bar item, e.g. after today's logged time changed.
    func refreshStatusItem() {
        updateStatusItem(isDue: isCheckInDue)
    }

    func setupCheckInPanel() {
        let panel = CheckInPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false

        let checkInView = CheckInPopoverView(store: store, onClose: { [weak self] in
            self?.closeCheckInPanel()
        })
        panel.contentView = NSHostingView(rootView: checkInView)
        self.checkInPanel = panel
    }

    func positionCheckInPanel(anchorButton: NSStatusBarButton? = nil) {
        guard let panel = checkInPanel else { return }
        let panelWidth: CGFloat = 380
        // Height from the SwiftUI content (ticket chips etc. change it); otherwise the content sits centered with a gap on top.
        let panelHeight = max(200, ceil(panel.contentView?.fittingSize.height ?? 320))
        let mouseLoc = NSEvent.mouseLocation

        if let button = anchorButton,
           let btnWin = button.window,
           let btnScreen = btnWin.screen,
           NSMouseInRect(mouseLoc, btnScreen.frame, false) {
            // Under statusbar button on the button's screen
            var x = btnWin.frame.midX - (panelWidth / 2)
            var y = btnWin.frame.minY - panelHeight - 8

            let minX = btnScreen.visibleFrame.minX + 8
            let maxX = btnScreen.visibleFrame.maxX - panelWidth - 8
            let minY = btnScreen.visibleFrame.minY + 8
            let maxY = btnScreen.visibleFrame.maxY - panelHeight - 8
            x = max(minX, min(maxX, x))
            y = max(minY, min(maxY, y))

            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        } else {
            // Timer prompt or ⌘K: active monitor (where the mouse is!)
            let screen = AppDelegate.activeScreen()
            let minX = screen.visibleFrame.minX + 16
            let maxX = screen.visibleFrame.maxX - panelWidth - 16
            let x = max(minX, min(maxX, screen.visibleFrame.maxX - panelWidth - 20))
            let y = screen.visibleFrame.maxY - panelHeight - 16

            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }
    }

    /// Opened by the user (menu bar, ⌘K, shortcut, notification): takes the keyboard.
    func showCheckInPanel(anchorButton: NSStatusBarButton? = nil) {
        presentCheckIn(.manual, activate: true, anchorButton: anchorButton)
    }

    /// Shows the panel for `reason`. Without `activate` it only floats in front: whatever you are typing in
    /// stays focused until you click the panel (it is a non-activating panel).
    func presentCheckIn(_ reason: CheckInReason, activate: Bool, anchorButton: NSStatusBarButton? = nil) {
        store.requestCheckIn(reason)
        // Let SwiftUI lay out the new content first, so the panel gets the right height.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.checkInPanel else { return }
            self.positionCheckInPanel(anchorButton: anchorButton)
            if activate {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
    }

    func closeCheckInPanel() {
        checkInPanel?.orderOut(nil)
        // Closing counts as seen: no notification follows.
        cancelEscalation()
    }

    /// A check-in was saved (panel, notification reply or "same as before").
    func checkInAnswered() {
        isCheckInDue = false
        updateStatusItem(isDue: false)
        cancelEscalation()
    }

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

    /// The text for `key` in the app's language (German until the store is loaded).
    private func t(_ key: String, _ args: String...) -> String {
        L10n.string(key, args, language: store?.appLanguage ?? .de)
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
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in }
        registerNotificationCategories()
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

    /// An `id` prefixed "morning-prompt"/"endofday-prompt" opens the main window on click, anything else the check-in.
    private func postNotification(id: String, category: String? = nil, title: String, body: String) {
        guard notificationsAvailable else { return }
        let content = makeNotificationContent(title: title, body: body)
        if let category { content.categoryIdentifier = category }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func sendCheckInNotification() {
        if case .beforeLunch = store.checkInRequest.reason {
            postNotification(id: UUID().uuidString, category: AppDelegate.checkInCategory,
                             title: t("notification.lunch.title"), body: t("notification.lunch.body"))
            return
        }
        let minutes = store.reminderIntervalMinutes
        postNotification(id: UUID().uuidString, category: AppDelegate.checkInCategory,
                         title: t("notification.checkIn.title", "\(minutes)"), body: t("notification.checkIn.body"))
    }

    // UNUserNotificationCenterDelegate
    // The notification center may call these on any thread.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
            if id.starts(with: "morning-prompt") || id.starts(with: "endofday-prompt") {
                bringMainWindowToFront()
            } else {
                showCheckInPanel(anchorButton: nil)
            }
        }
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
            let morning = "morning-prompt-", endOfDay = "endofday-prompt-"
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

    @objc func togglePopover(_ sender: AnyObject?) {
        if checkInPanel?.isVisible == true {
            closeCheckInPanel()
        } else {
            showCheckInPanel(anchorButton: statusItem?.button)
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

    @objc func openCheckInFromMenu() {
        showCheckInPanel(anchorButton: nil)
    }

    @objc func showMainWindow(_ sender: Any?) {
        bringMainWindowToFront()
    }

    // MARK: - Go menu

    /// The previous day, or the previous week in the week overview.
    @objc func goPrevious() {
        if store.mainViewMode == .week { store.moveWeek(-1) } else { store.moveDay(-1) }
        bringMainWindowToFront()
    }

    /// The next day, or the next week in the week overview.
    @objc func goNext() {
        if store.mainViewMode == .week { store.moveWeek(1) } else { store.moveDay(1) }
        bringMainWindowToFront()
    }

    @objc func goToday() {
        store.selectToday()
        bringMainWindowToFront()
    }

    @objc func goDayView() {
        store.mainViewMode = .day
        bringMainWindowToFront()
    }

    @objc func goWeekView() {
        store.mainViewMode = .week
        bringMainWindowToFront()
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

    // MARK: - Away detection (idle, sleep, locked screen)

    /// Seconds since the last keyboard or mouse input in this login session.
    nonisolated static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Away right now: tracked as away, or idle long enough (detection on).
    var isAway: Bool {
        guard store?.awayDetectionEnabled == true else { return false }
        return awayTracker.isAway || AppDelegate.idleSeconds() >= awayTracker.minimumAway
    }

    func startAwayDetection() {
        awayTimer?.invalidate()
        awayTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAway() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.awayTracker.wentAway(at: Date()) }
            }
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.awayTracker.wentAway(at: Date()) }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let period = self.awayTracker.cameBack(at: Date()) else { return }
                self.handleBack(period)
            }
        }
    }

    func checkAway() {
        guard let store else { return }
        awayTracker.minimumAway = TimeInterval(store.awayMinimumMinutes * 60)
        if let period = awayTracker.update(now: Date(), idleSeconds: AppDelegate.idleSeconds()) {
            handleBack(period)
        }
    }

    /// Back at the Mac: ask what the gap was (break or work), then restart the interval.
    func handleBack(_ period: AwayPeriod) {
        cancelEscalation()
        guard store.shouldAskAbout(period) else { return }
        isCheckInDue = true
        updateStatusItem(isDue: true)
        presentCheckIn(.back(period), activate: false)
        startCheckInTimer()
    }

    // MARK: - Dock icon

    /// With the Dock icon hidden, Schichta lives in the menu bar only (the main window opens from the check-in panel).
    func applyDockVisibility() {
        let policy: NSApplication.ActivationPolicy = store.showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { NSApp.activate(ignoringOtherApps: true) }
    }

    // MARK: - Global shortcut

    func updateGlobalHotKey() {
        hotKey?.unregister()
        hotKey = nil
        guard store?.globalHotKeyEnabled == true else { return }
        hotKey = GlobalHotKey { [weak self] in
            guard let self else { return }
            if self.checkInPanel?.isKeyWindow == true {
                self.closeCheckInPanel()
            } else {
                self.showCheckInPanel()
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

    func bringMainWindowToFront() {
        guard let window else { return } // created at launch; missing only in tests
        let screen = AppDelegate.activeScreen()
        if !window.isVisible || window.screen != screen {
            AppDelegate.centerWindow(window, on: screen)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func sendMorningPromptNotification(for unbookedDay: String) {
        let dateStr = SchichtaCore.formatFullDate(unbookedDay, language: store?.appLanguage ?? .de)
        postNotification(id: "morning-prompt-\(unbookedDay)", category: AppDelegate.dayPromptCategory,
                         title: t("notification.morning.title"), body: t("notification.morning.body", dateStr))
    }

    func sendEndOfDayPromptNotification(for day: String) {
        let dateStr = SchichtaCore.formatFullDate(day, language: store?.appLanguage ?? .de)
        postNotification(id: "endofday-prompt-\(day)", category: AppDelegate.dayPromptCategory,
                         title: t("notification.endOfDay.title"), body: t("notification.endOfDay.body", dateStr))
    }

    @objc func testMorningPromptFromMenu() {
        store.triggerMorningPromptManually()
    }

    @objc func testEndOfDayPromptFromMenu() {
        store.triggerEndOfDayPromptManually()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringMainWindowToFront()
        return true
    }
}
