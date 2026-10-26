import Cocoa
import SwiftUI
import UserNotifications

// MARK: - AppDelegate & Statusbar Popover

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: NSWindow!
    var store: SchichtaStore!

    var statusItem: NSStatusItem?
    var checkInPanel: CheckInPanel?
    var settingsWindow: NSWindow?
    var checkInTimer: Timer?
    var promptTimer: Timer?
    var isCheckInDue: Bool = false

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
        guard !CommandLine.arguments.contains("--self-test") else { return }
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
                NSLog("Fehler beim Erstellen des Notification-Attachments: %@", error.localizedDescription)
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

    static func checkInWindowString(for date: Date = Date(), intervalMinutes: Int = 30, language: AppLanguage = .de) -> String {
        let start = date.addingTimeInterval(-Double(intervalMinutes * 60))
        let suffix = language == .de ? "\(intervalMinutes) Min. Check-in" : "\(intervalMinutes) min check-in"
        return "\(Berlin.clock.string(from: start)) – \(Berlin.clock.string(from: date)) · \(suffix)"
    }

    static func checkInCurrentTimeString(for date: Date = Date()) -> String {
        Berlin.clock.string(from: date)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.store = SchichtaStore()

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
        setupMainMenu()

        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettingsWindow() {
        showSettings(tab: store?.settingsSelectedTab ?? 0)
    }

    func showSettings(tab: Int) {
        store?.settingsSelectedTab = tab
        let targetScreen = AppDelegate.activeScreen()
        if let win = settingsWindow {
            win.title = (store?.appLanguage ?? .de) == .de ? "Einstellungen" : "Settings"
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
        win.title = (store.appLanguage) == .de ? "Einstellungen" : "Settings"
        win.contentView = NSHostingView(rootView: settingsView)
        win.isReleasedWhenClosed = false
        AppDelegate.centerWindow(win, on: targetScreen)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = win
    }

    func updateMenuLanguage() {
        setupMainMenu()
        if let win = settingsWindow {
            win.title = (store?.appLanguage ?? .de) == .de ? "Einstellungen" : "Settings"
        }
    }

    private func setupMainMenu() {
        let isDe = (store?.appLanguage ?? .de) == .de
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu

        appMenu.addItem(withTitle: isDe ? "Über Schichta" : "About Schichta", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: isDe ? "Einstellungen…" : "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: isDe ? "Check-in öffnen" : "Open Check-in", action: #selector(openCheckInFromMenu), keyEquivalent: "k")
        appMenu.addItem(withTitle: isDe ? "Hauptfenster anzeigen" : "Show Main Window", action: #selector(showMainWindow(_:)), keyEquivalent: "0")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: isDe ? "Morgen-Prompt (Vortag) testen" : "Test Morning Prompt (Prev Day)", action: #selector(testMorningPromptFromMenu), keyEquivalent: "")
        appMenu.addItem(withTitle: isDe ? "Feierabend-Prompt testen" : "Test End-of-Day Prompt", action: #selector(testEndOfDayPromptFromMenu), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: isDe ? "Schichta beenden" : "Quit Schichta", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem(); menu.addItem(editItem)
        let editMenu = NSMenu(title: isDe ? "Bearbeiten" : "Edit"); editItem.submenu = editMenu
        let editActions: [(String, String, String)] = isDe ? [
            ("Rückgängig", "undo:", "z"),
            ("Ausschneiden", "cut:", "x"),
            ("Kopieren", "copy:", "c"),
            ("Einfügen", "paste:", "v"),
            ("Alles auswählen", "selectAll:", "a")
        ] : [
            ("Undo", "undo:", "z"),
            ("Cut", "cut:", "x"),
            ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"),
            ("Select All", "selectAll:", "a")
        ]
        for (title, selector, key) in editActions {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
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
        let symbolName = isDue ? "clock.badge.checkmark" : "clock"
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let img = (NSImage(systemSymbolName: symbolName, accessibilityDescription: "Schichta")
            ?? NSImage(systemSymbolName: "clock", accessibilityDescription: "Schichta"))?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        button.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        button.title = isDue ? " Schichta •" : " Schichta"
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
        // Höhe aus dem SwiftUI-Inhalt (Ticket-Chips etc. ändern sie), sonst sitzt der Inhalt mittig mit Lücke oben.
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

    func showCheckInPanel(anchorButton: NSStatusBarButton? = nil) {
        positionCheckInPanel(anchorButton: anchorButton)
        NSApp.activate(ignoringOtherApps: true)
        checkInPanel?.makeKeyAndOrderFront(nil)
    }

    func closeCheckInPanel() {
        checkInPanel?.orderOut(nil)
    }

    /// Mitteilungen nur in der gebündelten App; im Selbsttest oder als nacktes Binary gibt es kein Notification Center.
    private var notificationsAvailable: Bool {
        !CommandLine.arguments.contains("--self-test") && Bundle.main.bundleIdentifier != nil
    }

    func setupNotificationCenter() {
        guard notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `id` mit Präfix "morning-prompt"/"endofday-prompt" öffnet beim Klick das Hauptfenster, sonst den Check-in.
    private func postNotification(id: String, de: (title: String, body: String), en: (title: String, body: String)) {
        guard notificationsAvailable else { return }
        let text = (store?.appLanguage ?? .de) == .de ? de : en
        let request = UNNotificationRequest(identifier: id, content: makeNotificationContent(title: text.title, body: text.body), trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func sendNotificationIfAllowed() {
        let minutes = store.reminderIntervalMinutes
        postNotification(id: UUID().uuidString,
                         de: ("Schichta · \(minutes) Minuten", "Was machst du gerade? Kurz in der Statusleiste festhalten."),
                         en: ("Schichta · \(minutes) minutes", "What are you working on? Log it quickly in the status bar."))
    }

    // UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            let id = response.notification.request.identifier
            if id.starts(with: "morning-prompt") || id.starts(with: "endofday-prompt") {
                self?.bringMainWindowToFront()
            } else {
                self?.showCheckInPanel(anchorButton: nil)
            }
        }
        completionHandler()
    }

    func startCheckInTimer() {
        checkInTimer?.invalidate()
        guard let store = store, store.timerEnabled else { return }
        let interval = TimeInterval(max(5, store.reminderIntervalMinutes) * 60)
        checkInTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.triggerCheckInPrompt()
        }
    }

    func snoozeCheckIn() {
        isCheckInDue = false
        updateStatusItem(isDue: false)
        closeCheckInPanel()
        if store.timerEnabled {
            startCheckInTimer()
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
        guard store.isCurrentlyWithinWorkingHours() else { return }
        isCheckInDue = true
        updateStatusItem(isDue: true)
        showCheckInPanel(anchorButton: nil)
        playCheckInSound()
        sendNotificationIfAllowed()
    }

    @objc func openCheckInFromMenu() {
        showCheckInPanel(anchorButton: nil)
    }

    @objc func showMainWindow(_ sender: Any?) {
        bringMainWindowToFront()
    }

    // MARK: - Abschluss-Prompts (Morgen & Feierabend)

    func startPromptTimer() {
        promptTimer?.invalidate()
        // Check once directly 2 seconds after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkPeriodicPrompts()
        }
        // Background timer every 60 seconds
        promptTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkPeriodicPrompts()
        }
    }

    func checkPeriodicPrompts() {
        guard let store = store else { return }
        let now = Date()
        let today = SchichtaCore.berlinDay(from: now)
        let time = Berlin.calendar.dateComponents([.hour, .minute], from: now)
        let currentHour = time.hour!
        let currentTotalMinutes = currentHour * 60 + time.minute!

        // Prompt A: Morgen-Prompt (Vortag noch nicht gebucht)
        if store.morningPromptEnabled && store.isWorkingDay(today) && currentHour >= store.morningPromptHour && store.lastMorningPromptDate != today {
            if let unbookedPrev = store.unbookedPreviousDay(today: today) {
                store.lastMorningPromptDate = today
                triggerMorningPrompt(unbookedDay: unbookedPrev)
                return
            }
        }

        // Prompt B: Feierabend-Abschluss
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

    func bringMainWindowToFront() {
        let screen = AppDelegate.activeScreen()
        if !window.isVisible || window.screen != screen {
            AppDelegate.centerWindow(window, on: screen)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func sendMorningPromptNotification(for unbookedDay: String) {
        let dateStr = SchichtaCore.formatFullDate(unbookedDay, language: store?.appLanguage ?? .de)
        postNotification(id: "morning-prompt-\(unbookedDay)",
                         de: ("Schichta · Vortag noch offen", "Deine Buchungen vom \(dateStr) sind noch nicht abgeschlossen."),
                         en: ("Schichta · Previous day still unbooked", "Your bookings from \(dateStr) have not been finalized yet."))
    }

    func sendEndOfDayPromptNotification(for day: String) {
        let dateStr = SchichtaCore.formatFullDate(day, language: store?.appLanguage ?? .de)
        postNotification(id: "endofday-prompt-\(day)",
                         de: ("Schichta · Feierabend-Abschluss", "Zeit, deine heutigen Buchungen für \(dateStr) abzuschließen!"),
                         en: ("Schichta · End of day sign-off", "Time to finalize today's bookings for \(dateStr)!"))
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
