import Cocoa

extension AppDelegate {
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
}
