import Foundation

// MARK: - Shared Helpers (Zeitzone, Fehler, Pfade, Prozesse)

/// Alle Tage und Uhrzeiten der App gelten in Europe/Berlin.
enum Berlin {
    static let timeZone = TimeZone(identifier: "Europe/Berlin")!

    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }()

    /// Erzeugt einen Formatter in Berlin-Zeit. Geteilte Instanzen nur lesend nutzen, dann sind sie threadsicher.
    static func formatter(_ format: String, locale: String = "en_US_POSIX") -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.timeZone = timeZone
        f.dateFormat = format
        f.isLenient = false
        return f
    }

    /// YYYY-MM-DD
    static let day = formatter("yyyy-MM-dd")
    static let isoSeconds = formatter("yyyy-MM-dd'T'HH:mm:ssXXXXX")
    static let clock = formatter("HH:mm")
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
