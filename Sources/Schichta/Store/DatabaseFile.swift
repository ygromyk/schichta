import Foundation

/// Reads and writes schichta.json. A file that exists but cannot be read is never overwritten:
/// it is moved aside first, so a bad edit or a newer format can't silently wipe the entries.
/// Each day's first save also copies the previous file into Backups/ (the last `keptBackups` days are kept).
struct DatabaseFile {
    let url: URL
    var keptBackups = 7

    enum LoadResult {
        case loaded(Database)
        case missing
        /// `movedTo` is nil if the file could not be moved aside; it must then not be overwritten.
        case unreadable(error: Error, movedTo: URL?)
    }

    var backupsDirectory: URL {
        url.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try SchichtaCore.validate(database: JSONDecoder().decode(Database.self, from: data)))
        } catch {
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("schichta.unreadable-\(Self.timestamp()).json")
            let moved = (try? FileManager.default.moveItem(at: url, to: aside)) != nil
            return .unreadable(error: error, movedTo: moved ? aside : nil)
        }
    }

    func save(_ database: Database, today: String = SchichtaCore.day()) throws {
        let valid = try SchichtaCore.validate(database: database)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(valid)
        backUpOncePerDay(today: today)
        try data.write(to: url, options: .atomic)
    }

    /// Copies the current file to Backups/schichta-<today>.json unless today's backup exists, then prunes old ones.
    /// Best effort: a failed backup never blocks saving.
    private func backUpOncePerDay(today: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let target = backupsDirectory.appendingPathComponent("schichta-\(today).json")
        guard !fm.fileExists(atPath: target.path) else { return }
        try? fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try? fm.copyItem(at: url, to: target)

        // Names sort by date (schichta-YYYY-MM-DD.json), so the oldest come first.
        let backups = ((try? fm.contentsOfDirectory(atPath: backupsDirectory.path)) ?? [])
            .filter { $0.hasPrefix("schichta-") && $0.hasSuffix(".json") }
            .sorted()
        for name in backups.dropLast(keptBackups) {
            try? fm.removeItem(at: backupsDirectory.appendingPathComponent(name))
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppTime.timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
