import AppKit

enum ActivePrompt: Equatable {
    case none
    case morning(unbookedDay: String)
    case endOfDay(day: String)
}

/// Der laufende AppDelegate; `nil` in Tests, wo keine NSApplication gestartet wurde.
func appDelegate() -> AppDelegate? {
    NSApp?.delegate as? AppDelegate
}

// MARK: - SchichtaStore (Observable Store)

class SchichtaStore: ObservableObject {
    @Published var database: Database = Database()
    @Published var selectedDay: String = SchichtaCore.day()
    @Published var selectedDate: Date = Date()

    // 1. Language
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: "Schichta.AppLanguage")
            appDelegate()?.updateMenuLanguage()
        }
    }

    static let timeZoneKey = "Schichta.TimeZone"

    /// Time zone for day boundaries and times: an identifier such as "America/New_York", or "" for the system zone.
    /// Changing it switches the app-wide `AppTime`; the store's init does not, so tests can create stores freely.
    @Published var timeZoneIdentifier: String {
        didSet {
            defaults.set(timeZoneIdentifier, forKey: SchichtaStore.timeZoneKey)
            AppTime.use(AppTime.zone(forIdentifier: timeZoneIdentifier))
            selectDay(selectedDay)
        }
    }

    // 2. Working days (1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat)
    @Published var workingDays: Set<Int> {
        didSet {
            defaults.set(Array(workingDays).sorted(), forKey: "Schichta.WorkingDays")
        }
    }

    // 3. Normal work hours & target
    @Published var dailyTargetMinutes: Int {
        didSet {
            let clamped = max(60, min(1440, dailyTargetMinutes))
            if dailyTargetMinutes != clamped {
                dailyTargetMinutes = clamped
                return
            }
            defaults.set(dailyTargetMinutes, forKey: "Schichta.DailyTargetMinutes")
        }
    }
    @Published var workStartHour: Int {
        didSet {
            defaults.set(workStartHour, forKey: "Schichta.WorkStartHour")
        }
    }
    @Published var workStartMinute: Int {
        didSet {
            defaults.set(workStartMinute, forKey: "Schichta.WorkStartMinute")
        }
    }
    @Published var workEndHour: Int {
        didSet {
            defaults.set(workEndHour, forKey: "Schichta.WorkEndHour")
            defaults.set(workEndHour, forKey: "Schichta.EndOfDayPromptHour")
        }
    }
    @Published var workEndMinute: Int {
        didSet {
            defaults.set(workEndMinute, forKey: "Schichta.WorkEndMinute")
            defaults.set(workEndMinute, forKey: "Schichta.EndOfDayPromptMinute")
        }
    }
    @Published var onlyPromptDuringWorkHours: Bool {
        didSet {
            defaults.set(onlyPromptDuringWorkHours, forKey: "Schichta.OnlyPromptDuringWorkHours")
        }
    }

    // 4. Prompts & Check-in settings
    @Published var timerEnabled: Bool {
        didSet {
            defaults.set(timerEnabled, forKey: "Schichta.TimerEnabled")
            appDelegate()?.startCheckInTimer()
        }
    }
    @Published var reminderIntervalMinutes: Int {
        didSet {
            let clamped = max(5, min(240, reminderIntervalMinutes))
            if reminderIntervalMinutes != clamped {
                reminderIntervalMinutes = clamped
                return
            }
            defaults.set(reminderIntervalMinutes, forKey: "Schichta.ReminderIntervalMinutesV2")
            appDelegate()?.startCheckInTimer()
        }
    }
    @Published var defaultCheckInMode: CheckInMode {
        didSet {
            defaults.set(defaultCheckInMode.rawValue, forKey: "Schichta.DefaultCheckInMode")
        }
    }
    @Published var morningPromptEnabled: Bool {
        didSet {
            defaults.set(morningPromptEnabled, forKey: "Schichta.MorningPromptEnabled")
        }
    }
    @Published var endOfDayPromptEnabled: Bool {
        didSet {
            defaults.set(endOfDayPromptEnabled, forKey: "Schichta.EndOfDayPromptEnabled")
        }
    }
    static let availableSounds: [String] = ["Glass", "Tink", "Pop", "Purr", "Ping", "Hero", "Submarine"]
    @Published var checkInSoundEnabled: Bool {
        didSet {
            defaults.set(checkInSoundEnabled, forKey: "Schichta.CheckInSoundEnabled")
        }
    }
    @Published var checkInSoundName: String {
        didSet {
            defaults.set(checkInSoundName, forKey: "Schichta.CheckInSoundName")
        }
    }

    // 5. Git & User settings
    @Published var gitAuthorFilter: String {
        didSet {
            defaults.set(gitAuthorFilter, forKey: "Schichta.GitAuthorFilter")
        }
    }
    @Published var gitProjectsRoot: String {
        didSet {
            defaults.set(gitProjectsRoot, forKey: "Schichta.GitProjectsRoot")
        }
    }
    // Tracked Repositories V1
    @Published var trackedRepos: [TrackedRepo] {
        didSet {
            saveTrackedRepos()
        }
    }

    // External Hooks
    @Published var hookShellCommand: String {
        didSet {
            defaults.set(hookShellCommand, forKey: "Schichta.HookShellCommand")
        }
    }
    @Published var hookWebhookURL: String {
        didSet {
            defaults.set(hookWebhookURL, forKey: "Schichta.HookWebhookURL")
        }
    }
    @Published var aiCommand: String {
        didSet {
            defaults.set(aiCommand, forKey: "Schichta.AICommand")
        }
    }
    @Published var aiToolId: String {
        didSet {
            defaults.set(aiToolId, forKey: "Schichta.AIToolId")
        }
    }
    @Published var aiSummaryDay: String = ""
    @Published var aiSummaryText: String = ""
    @Published var aiQuestions: [String] = []
    @Published var hookAutoTriggerOnBook: Bool {
        didSet {
            defaults.set(hookAutoTriggerOnBook, forKey: "Schichta.HookAutoTriggerOnBook")
        }
    }
    @Published var lastHookResult: String = ""

    // UI Tab navigation for Settings (0: General, 1: WorkHours, 2: GitRepos, 3: Hooks)
    @Published var settingsSelectedTab: Int = 0

    // Inspector
    @Published var inspectedGitResult: [String: Any]? = nil
    @Published var isInspectingGit: Bool = false

    var hasExternalHookConfigured: Bool {
        !hookShellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !hookWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @Published var morningPromptHour: Int {
        didSet {
            defaults.set(morningPromptHour, forKey: "Schichta.MorningPromptHour")
        }
    }
    @Published var lastEndOfDayPromptDate: String {
        didSet {
            defaults.set(lastEndOfDayPromptDate, forKey: "Schichta.LastEndOfDayPromptDate")
        }
    }
    @Published var lastMorningPromptDate: String {
        didSet {
            defaults.set(lastMorningPromptDate, forKey: "Schichta.LastMorningPromptDate")
        }
    }

    @Published var activePrompt: ActivePrompt = .none
    @Published var proposals: [ProposedEntry] = []
    @Published var isSynthesizing: Bool = false
    @Published var toastMessage: String? = nil

    let storeURL: URL
    private let defaults: UserDefaults

    func t(_ de: String, _ en: String) -> String {
        appLanguage == .de ? de : en
    }

    func isWorkingDay(_ dayStr: String) -> Bool {
        guard SchichtaCore.isValidDate(dayStr) else { return false }
        let weekday = AppTime.calendar.component(.weekday, from: SchichtaCore.date(fromDay: dayStr))
        return workingDays.contains(weekday)
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

    /// `storeURL` und `defaults` sind austauschbar, damit der Selbsttest nie die echten Daten und Einstellungen berührt.
    init(storeURL: URL = AppPaths.support.appendingPathComponent("schichta.json"), defaults: UserDefaults = .standard) {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.storeURL = storeURL
        self.defaults = defaults

        // Language
        let initialLang: AppLanguage
        if let langRaw = defaults.string(forKey: "Schichta.AppLanguage"),
           let lang = AppLanguage(rawValue: langRaw) {
            initialLang = lang
        } else {
            initialLang = .de
        }
        self.appLanguage = initialLang
        self.timeZoneIdentifier = defaults.string(forKey: SchichtaStore.timeZoneKey) ?? ""

        // Working Days (1=Sun, 2=Mon... Standard: Mo-Fr [2, 3, 4, 5, 6])
        if let savedDays = defaults.array(forKey: "Schichta.WorkingDays") as? [Int], !savedDays.isEmpty {
            self.workingDays = Set(savedDays)
        } else {
            self.workingDays = Set([2, 3, 4, 5, 6])
        }

        // Daily target: Default 480 min (8h)
        let savedTarget = defaults.object(forKey: "Schichta.DailyTargetMinutes") as? Int
        self.dailyTargetMinutes = (savedTarget != nil && savedTarget! >= 60) ? savedTarget! : 480

        // Work Hours: Default 09:00 - 17:00
        let savedStartH = defaults.object(forKey: "Schichta.WorkStartHour") as? Int
        self.workStartHour = savedStartH ?? 9
        let savedStartM = defaults.object(forKey: "Schichta.WorkStartMinute") as? Int
        self.workStartMinute = savedStartM ?? 0

        let savedEndH = defaults.object(forKey: "Schichta.WorkEndHour") as? Int
            ?? defaults.object(forKey: "Schichta.EndOfDayPromptHour") as? Int
        self.workEndHour = savedEndH ?? 17
        let savedEndM = defaults.object(forKey: "Schichta.WorkEndMinute") as? Int
            ?? defaults.object(forKey: "Schichta.EndOfDayPromptMinute") as? Int
        self.workEndMinute = savedEndM ?? 0

        let savedOnly = defaults.object(forKey: "Schichta.OnlyPromptDuringWorkHours") as? Bool
        self.onlyPromptDuringWorkHours = savedOnly ?? true

        // Reminder Interval V2: Default 15 minutes
        let savedIntervalV2 = defaults.object(forKey: "Schichta.ReminderIntervalMinutesV2") as? Int
        if let val = savedIntervalV2, val >= 5 && val <= 240 {
            self.reminderIntervalMinutes = val
        } else {
            self.reminderIntervalMinutes = 15
            defaults.set(15, forKey: "Schichta.ReminderIntervalMinutesV2")
        }

        let savedTimer = defaults.object(forKey: "Schichta.TimerEnabled") as? Bool
        self.timerEnabled = savedTimer ?? true

        // Default CheckInMode: Default .both
        if let modeRaw = defaults.string(forKey: "Schichta.DefaultCheckInMode"),
           let mode = CheckInMode(rawValue: modeRaw) {
            self.defaultCheckInMode = mode
        } else {
            self.defaultCheckInMode = .both
        }

        let savedMorning = defaults.object(forKey: "Schichta.MorningPromptEnabled") as? Bool
        self.morningPromptEnabled = savedMorning ?? true

        let savedEndPrompt = defaults.object(forKey: "Schichta.EndOfDayPromptEnabled") as? Bool
        self.endOfDayPromptEnabled = savedEndPrompt ?? true

        let savedSoundEnabled = defaults.object(forKey: "Schichta.CheckInSoundEnabled") as? Bool
        self.checkInSoundEnabled = savedSoundEnabled ?? true

        let savedSoundName = defaults.string(forKey: "Schichta.CheckInSoundName")
        self.checkInSoundName = savedSoundName ?? "Glass"

        // Git & User settings
        self.gitAuthorFilter = defaults.string(forKey: "Schichta.GitAuthorFilter") ?? Activity.gitUserName()
        self.gitProjectsRoot = defaults.string(forKey: "Schichta.GitProjectsRoot") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("IdeaProjects").path

        // Tracked Repositories V1
        let initialRepos: [TrackedRepo]
        if let data = defaults.data(forKey: "Schichta.TrackedReposV1"),
           let decoded = try? JSONDecoder().decode([TrackedRepo].self, from: data),
           !decoded.isEmpty {
            initialRepos = decoded
        } else {
            // Keine vorkonfigurierten Repos; Nutzer fügt sie in den Einstellungen hinzu.
            initialRepos = []
        }
        self.trackedRepos = initialRepos

        // External Hooks
        self.hookShellCommand = defaults.string(forKey: "Schichta.HookShellCommand") ?? ""
        self.hookWebhookURL = defaults.string(forKey: "Schichta.HookWebhookURL") ?? ""
        if let savedCommand = defaults.string(forKey: "Schichta.AICommand") {
            self.aiCommand = savedCommand
            self.aiToolId = defaults.string(forKey: "Schichta.AIToolId") ?? ""
        } else {
            // Erster Start: das erste installierte eingebaute Werkzeug vorauswählen (Senden bleibt manuell).
            let firstInstalled = AITools.builtIns().first(where: \.installed)
            self.aiCommand = firstInstalled?.command ?? ""
            self.aiToolId = firstInstalled?.id ?? ""
        }
        self.hookAutoTriggerOnBook = defaults.bool(forKey: "Schichta.HookAutoTriggerOnBook")

        // Morning prompt hour: Default 9:00
        let savedMorningHour = defaults.object(forKey: "Schichta.MorningPromptHour") as? Int
        self.morningPromptHour = savedMorningHour ?? 9

        // Last prompt dates
        self.lastEndOfDayPromptDate = defaults.string(forKey: "Schichta.LastEndOfDayPromptDate") ?? ""
        self.lastMorningPromptDate = defaults.string(forKey: "Schichta.LastMorningPromptDate") ?? ""

        load()
    }

    func load() {
        if FileManager.default.fileExists(atPath: storeURL.path),
           let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode(Database.self, from: data),
           let validated = try? SchichtaCore.validate(database: decoded) {
            self.database = validated
        } else {
            self.database = Database(version: 1, entries: [], journal: [:])
            save()
        }
    }

    func save() {
        do {
            let valid = try SchichtaCore.validate(database: self.database)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(valid)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("Fehler beim Speichern der Schichta-Datenbank: %@", error.localizedDescription)
        }
    }

    func saveTrackedRepos() {
        if let data = try? JSONEncoder().encode(trackedRepos) {
            defaults.set(data, forKey: "Schichta.TrackedReposV1")
        }
    }

    func openSettings(tab: Int = 0) {
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
