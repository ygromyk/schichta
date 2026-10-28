import Foundation

// MARK: - Shared Helpers (time zone, errors, paths, processes)

/// All days (YYYY-MM-DD) and times use one time zone: the system zone unless another is chosen in Settings.
/// Calendar and formatters live in one immutable `State` behind a lock, so switching zones while a
/// background Git read formats dates never mixes two zones.
enum AppTime {
    final class State {
        let timeZone: TimeZone
        let calendar: Calendar
        let day: DateFormatter          // yyyy-MM-dd
        let isoSeconds: DateFormatter   // 2026-10-26T09:00:00+01:00
        let clock: DateFormatter        // HH:mm
        let weekday: [AppLanguage: DateFormatter]
        let fullDate: [AppLanguage: DateFormatter]

        init(_ zone: TimeZone) {
            timeZone = zone
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            calendar = cal
            func formatter(_ format: String, locale: String = "en_US_POSIX") -> DateFormatter {
                let f = DateFormatter()
                f.locale = Locale(identifier: locale)
                f.timeZone = zone
                f.dateFormat = format
                f.isLenient = false
                return f
            }
            day = formatter("yyyy-MM-dd")
            isoSeconds = formatter("yyyy-MM-dd'T'HH:mm:ssXXXXX")
            clock = formatter("HH:mm")
            weekday = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { ($0, formatter("EEEE", locale: $0.localeIdentifier)) })
            fullDate = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map {
                ($0, formatter($0 == .de ? "EEEE, d. MMMM yyyy" : "EEEE, MMMM d, yyyy", locale: $0.localeIdentifier))
            })
        }
    }

    private static let lock = NSLock()
    /// Only accessed under `lock`.
    private nonisolated(unsafe) static var current = State(.current)

    /// The active state; read once per operation so all values come from the same zone.
    static var state: State { lock.withLock { current } }
    static var timeZone: TimeZone { state.timeZone }
    static var calendar: Calendar { state.calendar }
    static var day: DateFormatter { state.day }
    static var isoSeconds: DateFormatter { state.isoSeconds }
    static var clock: DateFormatter { state.clock }

    /// Switches the app's time zone. Called by the app at launch and from Settings, and by tests that pin a zone.
    static func use(_ zone: TimeZone) {
        let next = State(zone)
        lock.withLock { current = next }
    }

    /// Settings value: a time zone identifier, or "" for the system zone.
    static func zone(forIdentifier identifier: String) -> TimeZone {
        identifier.isEmpty ? .current : (TimeZone(identifier: identifier) ?? .current)
    }
}

/// A user-facing text that is resolved later; whoever shows it picks the language.
struct LocalizedText: Equatable {
    private let key: String?
    private let args: [String]

    /// A key from Localizable.strings; `args` fill its `%1$@`, `%2$@`, …
    init(key: String, _ args: String...) {
        self.init(key: key, args: args)
    }
    init(key: String, args: [String]) {
        self.key = key
        self.args = args
    }
    /// The same text in both languages, e.g. a name.
    init(verbatim text: String) {
        key = nil
        args = [text]
    }

    func `in`(_ language: AppLanguage) -> String {
        guard let key else { return args[0] }
        return L10n.string(key, args, language: language)
    }
    var de: String { self.in(.de) }
    var en: String { self.in(.en) }
}

/// An error with a localized message. `localizedDescription` uses `AppLanguage.current`,
/// so errors thrown deep in the core read right wherever the UI shows them.
struct SchichtaError: LocalizedError {
    let text: LocalizedText
    init(_ key: String, _ args: String...) { text = LocalizedText(key: key, args: args) }
    init(_ text: LocalizedText) { self.text = text }
    var errorDescription: String? { text.in(AppLanguage.current) }
}

enum AppPaths {
    /// SCHICHTA_DATA_DIR runs Schichta on separate data (e.g. demo data for screenshots): the data folder
    /// moves there and settings go to their own defaults domain, so real entries and settings stay untouched.
    static let dataDirOverride: String? = ProcessInfo.processInfo.environment["SCHICHTA_DATA_DIR"].flatMap { $0.isEmpty ? nil : $0 }

    /// ~/Library/Application Support/Schichta, or SCHICHTA_DATA_DIR (created on demand).
    static let support: URL = {
        let dir: URL
        if let dataDirOverride {
            dir = URL(fileURLWithPath: dataDirOverride, isDirectory: true)
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            dir = base.appendingPathComponent("Schichta", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The app's settings, or the `local.schichta.data-dir` domain when SCHICHTA_DATA_DIR is set.
    static var defaults: UserDefaults {
        dataDirOverride == nil ? .standard : UserDefaults(suiteName: "local.schichta.data-dir")!
    }
}

/// Runs a program with a timeout and collects its output.
/// stdin is written concurrently and the timeout is armed first: if the command never reads stdin,
/// writing into a full pipe (> 64 KB) would otherwise block forever. The stdin pipe never raises SIGPIPE
/// (F_SETNOSIGPIPE), so a command that exits early causes a write error instead of a crash.
/// The pipe pumps run on their own threads, not on a dispatch queue: concurrent queues get about one thread
/// per core, so once that many callers block in `run` (e.g. parallel tests), their pumps never start and every call hangs.
enum Shell {
    /// Serial queues always get a thread; the timeout work items are tiny.
    private static let timeouts = DispatchQueue(label: "local.schichta.shell-timeouts")

    /// Runs `work` on a new thread, tracked by `group`.
    private static func pump(_ group: DispatchGroup, _ work: @escaping () -> Void) {
        group.enter()
        // The caller waits on `group` before it reads anything `work` wrote, so the hand-off is race-free.
        nonisolated(unsafe) let work = work
        Thread.detachNewThread {
            work()
            group.leave()
        }
    }

    struct Output {
        let status: Int32
        let stdout: Data
        let stderr: Data
        var text: String { String(decoding: stdout, as: UTF8.self) }
    }

    static func run(
        _ executable: String,
        _ arguments: [String],
        stdin: Data? = nil,
        environment: [String: String]? = nil,
        directory: URL? = nil,
        mergeStderr: Bool = false,
        timeout: TimeInterval
    ) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let directory { process.currentDirectoryURL = directory }
        let out = Pipe(), err = Pipe()
        let input = stdin == nil ? nil : Pipe()
        process.standardOutput = out
        process.standardError = mergeStderr ? out : err
        process.standardInput = input ?? FileHandle.nullDevice
        if let input {
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        }
        try process.run()

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        timeouts.asyncAfter(deadline: .now() + timeout, execute: killer)
        let background = DispatchGroup()
        if let input, let stdin {
            pump(background) {
                try? input.fileHandleForWriting.write(contentsOf: stdin)
                try? input.fileHandleForWriting.close()
            }
        }
        var errData = Data()
        if !mergeStderr {
            pump(background) { errData = err.fileHandleForReading.readDataToEndOfFile() }
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        // Close the read end in case the command exited without reading stdin: a blocked write then fails.
        try? input?.fileHandleForReading.close()
        background.wait()
        return Output(status: process.terminationStatus, stdout: outData, stderr: errData)
    }
}
