import Foundation

// MARK: - Shared Helpers (Zeitzone, Fehler, Pfade, Prozesse)

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
    private static var current = State(.current)

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

struct SchichtaError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum AppPaths {
    /// ~/Library/Application Support/Schichta (wird bei Bedarf angelegt).
    static let support: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Schichta", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// Startet ein Programm mit Zeitlimit und sammelt die Ausgabe.
/// stdin wird nebenläufig geschrieben und das Zeitlimit vorher gestartet: Liest der Befehl stdin nicht,
/// blockiert sonst das Schreiben einer vollen Pipe (> 64 KB) für immer. Die stdin-Pipe löst kein SIGPIPE aus
/// (F_SETNOSIGPIPE), ein vorzeitig beendeter Befehl führt daher nur zu einem Schreibfehler statt zum Absturz.
enum Shell {
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
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let background = DispatchGroup()
        if let input, let stdin {
            DispatchQueue.global().async(group: background) {
                try? input.fileHandleForWriting.write(contentsOf: stdin)
                try? input.fileHandleForWriting.close()
            }
        }
        var errData = Data()
        if !mergeStderr {
            DispatchQueue.global().async(group: background) { errData = err.fileHandleForReading.readDataToEndOfFile() }
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        // Lese-Ende schließen, falls der Befehl beendet ist, ohne stdin zu lesen: Das hängende Schreiben bricht dann ab.
        try? input?.fileHandleForReading.close()
        background.wait()
        return Output(status: process.terminationStatus, stdout: outData, stderr: errData)
    }
}
