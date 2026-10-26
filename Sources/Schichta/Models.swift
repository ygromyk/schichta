import Foundation

// MARK: - Tracked Git Repository Model

struct TrackedRepo: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var path: String          // Absolute path of the Git directory, e.g. "/Users/me/Projects/example-app"
    var projectName: String   // Project name for reports & external hooks, e.g. "Example App"
    var defaultTicket: String // Optional default ticket for commits without a ticket in their message (e.g. "PROJ-2800")
    var enabled: Bool = true

    var folderName: String { URL(fileURLWithPath: path).lastPathComponent }
    var displayLabel: String { projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? folderName : projectName }

    enum CodingKeys: String, CodingKey {
        case id, path, projectName, defaultTicket, enabled
    }

    init(id: String = UUID().uuidString, path: String, projectName: String = "", defaultTicket: String = "", enabled: Bool = true) {
        self.id = id
        self.path = path
        self.projectName = projectName
        self.defaultTicket = defaultTicket
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.path = try container.decode(String.self, forKey: .path)
        self.projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
        self.defaultTicket = try container.decodeIfPresent(String.self, forKey: .defaultTicket) ?? ""
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

// MARK: - Data Models

struct Entry: Identifiable, Codable, Equatable {
    var id: String
    var date: String // YYYY-MM-DD
    var ticket: String
    var description: String
    var minutes: Int
    var estimated: Bool
    var project: String = ""

    enum CodingKeys: String, CodingKey {
        case id, date, ticket, description, minutes, estimated, project
    }

    init(id: String = UUID().uuidString, date: String, ticket: String, description: String, minutes: Int, estimated: Bool, project: String = "") {
        self.id = id
        self.date = date
        self.ticket = ticket
        self.description = description
        self.minutes = minutes
        self.estimated = estimated
        self.project = project
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.date = try container.decode(String.self, forKey: .date)
        self.ticket = try container.decode(String.self, forKey: .ticket)
        self.description = try container.decode(String.self, forKey: .description)
        self.minutes = try container.decode(Int.self, forKey: .minutes)
        self.estimated = try container.decode(Bool.self, forKey: .estimated)
        self.project = try container.decodeIfPresent(String.self, forKey: .project) ?? ""
    }
}

/// A working day you don't work: no target, no prompts, never "not booked".
enum Absence: String, Codable, CaseIterable {
    case vacation, sick, holiday

    func title(for language: AppLanguage) -> String {
        switch self {
        case .vacation: return LocalizedText("Urlaub", "Vacation").in(language)
        case .sick: return LocalizedText("Krank", "Sick").in(language)
        case .holiday: return LocalizedText("Feiertag", "Holiday").in(language)
        }
    }

    var icon: String {
        switch self {
        case .vacation: return "sun.max"
        case .sick: return "cross.case"
        case .holiday: return "flag"
        }
    }
}

struct JournalItem: Codable, Equatable {
    var notes: String = ""
    var logs: String = ""
    var answer: String = ""
    var booked: Bool = false
    var absence: Absence? = nil

    enum CodingKeys: String, CodingKey {
        case notes, logs, answer, booked, absence
    }

    init(notes: String = "", logs: String = "", answer: String = "", booked: Bool = false, absence: Absence? = nil) {
        self.notes = notes
        self.logs = logs
        self.answer = answer
        self.booked = booked
        self.absence = absence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.logs = try container.decodeIfPresent(String.self, forKey: .logs) ?? ""
        self.answer = try container.decodeIfPresent(String.self, forKey: .answer) ?? ""
        self.booked = try container.decodeIfPresent(Bool.self, forKey: .booked) ?? false
        // Lenient: an unknown kind (from a newer version) reads as no absence instead of failing the whole file.
        self.absence = (try? container.decodeIfPresent(Absence.self, forKey: .absence)) ?? nil
    }
}

struct Database: Codable, Equatable {
    var version: Int = 1
    var entries: [Entry] = []
    var journal: [String: JournalItem] = [:]
}

struct ProposedEntry: Identifiable, Equatable {
    var id: String
    var ticket: String
    var description: String
    var minutes: Int
    var estimated: Bool = true
    var source: LocalizedText
    var project: String = ""
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case de = "de"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .de: return "Deutsch"
        case .en: return "English"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .de: return "de_DE"
        case .en: return "en_US"
        }
    }

    /// German if the system's preferred language is German, otherwise English.
    static var system: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("de") == true ? .de : .en
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var _current: AppLanguage = .system

    /// The UI language for texts produced outside the store, such as error messages.
    /// Set by the app at launch and when the setting changes; the store's init leaves it alone.
    static var current: AppLanguage {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }
}

enum CheckInMode: String, CaseIterable, Identifiable {
    case both = "entryAndNote"
    case noteOnly = "noteOnly"

    var id: String { rawValue }

    func title(for lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.both, .de): return "Als Eintrag + Notiz"
        case (.both, .en): return "As entry + note"
        case (.noteOnly, .de): return "Nur als Notiz"
        case (.noteOnly, .en): return "Note only"
        }
    }
}
