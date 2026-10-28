import Cocoa
import SwiftUI

extension AppDelegate {
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
        // Closing counts as seen: no notification follows, and one already shown goes away.
        cancelEscalation()
        removeCheckInNotification()
    }

    /// A check-in was saved (panel, notification reply or "same as before").
    func checkInAnswered() {
        isCheckInDue = false
        updateStatusItem(isDue: false)
        cancelEscalation()
        removeCheckInNotification()
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if checkInPanel?.isVisible == true {
            closeCheckInPanel()
        } else {
            showCheckInPanel(anchorButton: statusItem?.button)
        }
    }
}
