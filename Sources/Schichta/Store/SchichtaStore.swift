import AppKit

enum ActivePrompt: Equatable {
    case none
    case morning(unbookedDay: String)
    case endOfDay(day: String)
}

/// The running AppDelegate; `nil` in tests, where no NSApplication was started.
@MainActor
func appDelegate() -> AppDelegate? {
    NSApp?.delegate as? AppDelegate
}

// MARK: - SchichtaStore (Observable Store)

@MainActor
class SchichtaStore: ObservableObject {
    @Published var database: Database = Database()
    @Published var selectedDay: String = SchichtaCore.day()
    @Published var selectedDate: Date = Date()

    // Settings live in UserDefaults through `@Setting`; the keys are part of the saved state, so never rename them.

    // 1. Language
    @Setting("Schichta.AppLanguage") var appLanguage: AppLanguage = .system {
        didSet {
            AppLanguage.current = appLanguage
            appDelegate()?.updateMenuLanguage()
        }
    }

    static let timeZoneKey = "Schichta.TimeZone"

    /// Time zone for day boundaries and times: an identifier such as "America/New_York", or "" for the system zone.
    /// Changing it switches the app-wide `AppTime`; the store's init does not, so tests can create stores freely.
    @Setting(SchichtaStore.timeZoneKey) var timeZoneIdentifier: String = "" {
        didSet {
            AppTime.use(AppTime.zone(forIdentifier: timeZoneIdentifier))
            selectDay(selectedDay)
        }
    }

    // 2. Working days (1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat)
    @Setting("Schichta.WorkingDays") var workingDays: Set<Int> = [2, 3, 4, 5, 6]

    // 3. Normal work hours & target
    @Setting("Schichta.DailyTargetMinutes", clamp: { max(60, min(1440, $0)) }) var dailyTargetMinutes: Int = 480
    /// Overtime account: counted from this day (YYYY-MM-DD), or from the first entry when empty.
    @Setting("Schichta.OvertimeStartDate") var overtimeStartDate: String = ""
    /// Balance carried in on the start date, in minutes (negative = minus hours).
    @Setting("Schichta.OvertimeOpeningMinutes") var overtimeOpeningMinutes: Int = 0
    @Setting("Schichta.WorkStartHour") var workStartHour: Int = 9
    @Setting("Schichta.WorkStartMinute") var workStartMinute: Int = 0
    @Setting("Schichta.WorkEndHour") var workEndHour: Int = 17
    @Setting("Schichta.WorkEndMinute") var workEndMinute: Int = 0
    @Setting("Schichta.OnlyPromptDuringWorkHours") var onlyPromptDuringWorkHours: Bool = true
    static let timeSteps = [1, 5, 10, 15, 30, 60]
    /// Every booked duration is a multiple of this (see `snapDuration`); also the size of the ± buttons.
    @Setting("Schichta.TimeStepMinutes", clamp: { SchichtaStore.timeSteps.contains($0) ? $0 : 15 }) var timeStepMinutes: Int = 15

    // 4. Prompts & Check-in settings
    @Setting("Schichta.TimerEnabled") var timerEnabled: Bool = true {
        didSet { appDelegate()?.startCheckInTimer() }
    }
    @Setting("Schichta.ReminderIntervalMinutesV2", clamp: { max(5, min(240, $0)) }) var reminderIntervalMinutes: Int = 15 {
        didSet { appDelegate()?.startCheckInTimer() }
    }
    @Setting("Schichta.DefaultCheckInMode") var defaultCheckInMode: CheckInMode = .both
    @Setting("Schichta.MorningPromptEnabled") var morningPromptEnabled: Bool = true
    @Setting("Schichta.MorningPromptHour") var morningPromptHour: Int = 9
    @Setting("Schichta.EndOfDayPromptEnabled") var endOfDayPromptEnabled: Bool = true
    @Setting("Schichta.LastEndOfDayPromptDate") var lastEndOfDayPromptDate: String = ""
    @Setting("Schichta.LastMorningPromptDate") var lastMorningPromptDate: String = ""
    static let availableSounds: [String] = ["Glass", "Tink", "Pop", "Purr", "Ping", "Hero", "Submarine"]
    @Setting("Schichta.CheckInSoundEnabled") var checkInSoundEnabled: Bool = true
    @Setting("Schichta.CheckInSoundName") var checkInSoundName: String = "Glass"
    /// "Off to lunch?" prompt asking for the morning.
    @Setting("Schichta.LunchPromptEnabled") var lunchPromptEnabled: Bool = true
    @Setting("Schichta.LunchHour", clamp: { max(10, min(15, $0)) }) var lunchHour: Int = 12
    @Setting("Schichta.LunchMinute", clamp: { max(0, min(59, $0)) }) var lunchMinute: Int = 0
    @Setting("Schichta.LastLunchPromptDate") var lastLunchPromptDate: String = ""
    /// Ask "what was that?" after time away from the Mac (idle, sleep, locked screen).
    @Setting("Schichta.AwayDetectionEnabled") var awayDetectionEnabled: Bool = true
    @Setting("Schichta.AwayMinimumMinutes", clamp: { max(5, min(60, $0)) }) var awayMinimumMinutes: Int = 10
    /// Off: no Dock icon and no ⌘Tab entry; Schichta stays in the menu bar.
    @Setting("Schichta.ShowInDock") var showInDock: Bool = true {
        didSet { appDelegate()?.applyDockVisibility() }
    }
    /// ⌥⌘K opens the check-in from any app.
    @Setting("Schichta.GlobalHotKeyEnabled") var globalHotKeyEnabled: Bool = true {
        didSet { appDelegate()?.updateGlobalHotKey() }
    }

    // 5. Git & User settings
    /// Filled from `git config user.name` on first launch (see `prepareDefaults`).
    @Setting("Schichta.GitAuthorFilter") var gitAuthorFilter: String = ""
    /// Last folder scanned for repositories; empty until the user picks one.
    @Setting("Schichta.GitProjectsRoot") var gitProjectsRoot: String = ""
    @Setting("Schichta.TrackedReposV1") var trackedRepos: [TrackedRepo] = []

    // 6. External hooks & AI
    @Setting("Schichta.HookShellCommand") var hookShellCommand: String = ""
    @Setting("Schichta.HookWebhookURL") var hookWebhookURL: String = ""
    @Setting("Schichta.HookAutoTriggerOnBook") var hookAutoTriggerOnBook: Bool = false
    /// Preselected on first launch with the first installed built-in tool (see `prepareDefaults`).
    @Setting("Schichta.AICommand") var aiCommand: String = ""
    @Setting("Schichta.AIToolId") var aiToolId: String = ""

    /// `minutes` rounded to the time step.
    func snapDuration(_ minutes: Int) -> Int {
        SchichtaCore.snapDuration(minutes, step: timeStepMinutes)
    }

    /// Quick duration buttons: 15m to 2h, rounded to the time step (duplicates dropped).
    var durationPresets: [Int] {
        var seen = Set<Int>()
        return [15, 30, 45, 60, 90, 120].map(snapDuration).filter { seen.insert($0).inserted }
    }

    var hasExternalHookConfigured: Bool {
        !hookShellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !hookWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Session state (not saved)

    @Published var aiSummaryDay: String = ""
    @Published var aiSummaryText: String = ""
    @Published var aiQuestions: [String] = []
    @Published var lastHookResult: String = ""
    @Published var settingsSelectedTab: SettingsTab = .general
    @Published var mainViewMode: MainViewMode = .day

    // Inspector
    @Published var inspectedGitResult: GitActivityResult? = nil
    @Published var isInspectingGit: Bool = false

    @Published var activePrompt: ActivePrompt = .none
    /// The current opening of the check-in panel; a new value resets the panel.
    @Published var checkInRequest = CheckInRequest(reason: .manual)
    @Published var proposals: [ProposedEntry] = []
    @Published var isSynthesizing: Bool = false
    @Published var toastMessage: String? = nil
    /// Set when the data file could not be read at launch; shown as a banner until dismissed.
    @Published var storeProblem: String? = nil
    /// True when an unreadable data file could not be moved aside, so saving would overwrite it.
    private(set) var savingBlocked = false

    let storeURL: URL
    /// Read and written by `@Setting`.
    let defaults: UserDefaults

    /// The text for `key` in the store's language; `args` fill its `%1$@`, `%2$@`, …
    func t(_ key: String, _ args: String...) -> String {
        L10n.string(key, args, language: appLanguage)
    }

    /// An error's message in the store's language (Schichta errors carry both).
    func describe(_ error: Error) -> String {
        (error as? SchichtaError)?.text.in(appLanguage) ?? error.localizedDescription
    }

    /// A day you're expected to work: a working weekday that isn't marked as vacation, sick or holiday.
    /// Targets, prompts and "not booked" all follow this.
    func isWorkingDay(_ dayStr: String) -> Bool {
        isScheduledWorkday(dayStr) && absence(on: dayStr) == nil
    }

    /// One of the working weekdays from Settings, regardless of absences.
    func isScheduledWorkday(_ dayStr: String) -> Bool {
        guard SchichtaCore.isValidDate(dayStr) else { return false }
        let weekday = AppTime.calendar.component(.weekday, from: SchichtaCore.date(fromDay: dayStr))
        return workingDays.contains(weekday)
    }

    func absence(on day: String) -> Absence? {
        database.journal[day]?.absence
    }

    /// Marks `day` as vacation, sick or holiday, or (nil) as a normal day again.
    func setAbsence(_ absence: Absence?, on day: String) {
        var item = database.journal[day] ?? JournalItem()
        item.absence = absence
        database.journal[day] = item
        save()
        let date = SchichtaCore.formatGermanDate(day)
        if let absence {
            showToast("\(date): \(absence.title(for: appLanguage))")
        } else {
            showToast(t("store.isAWorkingDayAgain", "\(date)"))
        }
    }

    func isCurrentlyWithinWorkingHours(_ now: Date = Date()) -> Bool {
        let today = SchichtaCore.day(from: now)
        guard isWorkingDay(today) else { return false }
        guard onlyPromptDuringWorkHours else { return true }

        let time = AppTime.calendar.dateComponents([.hour, .minute], from: now)
        let curTotal = time.hour! * 60 + time.minute!
        let startTotal = workStartHour * 60 + workStartMinute
        let endTotal = workEndHour * 60 + workEndMinute
        return curTotal >= startTotal && curTotal <= endTotal
    }

    /// `storeURL` and `defaults` are injectable so tests never touch real entries or settings.
    init(storeURL: URL = AppPaths.support.appendingPathComponent("schichta.json"), defaults: UserDefaults = AppPaths.defaults) {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.storeURL = storeURL
        self.defaults = defaults
        SchichtaStore.prepareDefaults(defaults)
        load()
    }

    /// Moves settings from older keys and fills values that need detecting, once, before anything reads them.
    nonisolated static func prepareDefaults(_ defaults: UserDefaults) {
        // The work end used to be stored only as the end-of-day prompt time.
        for (key, oldKey) in [("Schichta.WorkEndHour", "Schichta.EndOfDayPromptHour"), ("Schichta.WorkEndMinute", "Schichta.EndOfDayPromptMinute")]
        where defaults.object(forKey: key) == nil {
            if let old = defaults.object(forKey: oldKey) { defaults.set(old, forKey: key) }
        }
        // Without a saved filter, use the Git author name, so no name is hard-coded. Kept unset while Git has none.
        if defaults.object(forKey: "Schichta.GitAuthorFilter") == nil {
            let name = Activity.gitUserName()
            if !name.isEmpty { defaults.set(name, forKey: "Schichta.GitAuthorFilter") }
        }
        // First launch: preselect the first installed built-in AI tool (sending stays manual).
        if defaults.object(forKey: "Schichta.AICommand") == nil, let tool = AITools.builtIns().first(where: \.installed) {
            defaults.set(tool.command, forKey: "Schichta.AICommand")
            defaults.set(tool.id, forKey: "Schichta.AIToolId")
        }
    }

    func load() {
        switch DatabaseFile(url: storeURL).load() {
        case .loaded(let database):
            self.database = database
        case .missing:
            self.database = Database()
            save()
        case .unreadable(let error, let movedTo):
            // Start empty, but never on top of the unreadable file: it was moved aside, or saving stays off.
            self.database = Database()
            NSLog("Could not read the Schichta database: %@", error.localizedDescription)
            let reason = describe(error)
            if let movedTo {
                storeProblem = t("store.theDataFileCouldNot", "\(reason)", "\(movedTo.lastPathComponent)")
            } else {
                savingBlocked = true
                storeProblem = t("store.theDataFileCouldNot2", "\(reason)")
            }
        }
    }

    func save() {
        guard !savingBlocked else { return }
        do {
            try DatabaseFile(url: storeURL).save(database)
        } catch {
            NSLog("Could not save the Schichta database: %@", error.localizedDescription)
            showToast(t("store.savingFailed", "\(error.localizedDescription)"))
        }
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([storeURL.deletingLastPathComponent()])
    }

    func openSettings(tab: SettingsTab = .general) {
        self.settingsSelectedTab = tab
        appDelegate()?.showSettings(tab: tab)
    }

    func showToast(_ message: String) {
        self.toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

}
