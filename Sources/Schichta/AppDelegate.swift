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
    /// One notification per kind: a new one replaces the one still in Notification Center.
    static let checkInNotificationID = "checkin"
    static let morningPromptIDPrefix = "morning-prompt-"
    static let endOfDayPromptIDPrefix = "endofday-prompt-"
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

    static let notificationIconURL = AppPaths.support.appendingPathComponent("notification-icon.png")

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

    /// The text for `key` in the app's language (German until the store is loaded).
    func t(_ key: String, _ args: String...) -> String {
        L10n.string(key, args, language: store?.appLanguage ?? .de)
    }

    @objc func showMainWindow(_ sender: Any?) {
        bringMainWindowToFront()
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

    func bringMainWindowToFront() {
        guard let window else { return } // created at launch; missing only in tests
        let screen = AppDelegate.activeScreen()
        if !window.isVisible || window.screen != screen {
            AppDelegate.centerWindow(window, on: screen)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Back from System Settings, say: the notification permission may have changed.
    func applicationDidBecomeActive(_ notification: Notification) {
        refreshNotificationAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringMainWindowToFront()
        return true
    }
}
