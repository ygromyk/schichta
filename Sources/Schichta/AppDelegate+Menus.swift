import Cocoa

extension AppDelegate {
    func updateMenuLanguage() {
        setupMainMenu()
        registerNotificationCategories()
        if let win = settingsWindow {
            win.title = t("app.settingsTitle")
        }
    }

    func setupMainMenu() {
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

    @objc func openCheckInFromMenu() {
        showCheckInPanel(anchorButton: nil)
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

    @objc func testMorningPromptFromMenu() {
        store.triggerMorningPromptManually()
    }

    @objc func testEndOfDayPromptFromMenu() {
        store.triggerEndOfDayPromptManually()
    }
}
