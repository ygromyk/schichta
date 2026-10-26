import Foundation

// MARK: - SchichtaCore (Parsing, Formatting, Validation & BCS Report)

enum SchichtaCore {
    static func parseMinutes(_ input: String) throws -> Int {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else {
            throw SchichtaError("Dauer darf nicht leer sein.", en: "Duration must not be empty.")
        }

        var total: Int? = nil

        // 1) HH:MM (e.g. 1:30, 01:05)
        if s.range(of: #"^\d{1,2}:[0-5]\d$"#, options: .regularExpression) != nil {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                total = parts[0] * 60 + parts[1]
            }
        }
        // 2) Decimal hours (e.g. 1,5 or 1.25)
        else if s.range(of: #"^\d{1,2}([.,]\d{1,2})?$"#, options: .regularExpression) != nil {
            let normalized = s.replacingOccurrences(of: ",", with: ".")
            if let val = Double(normalized) {
                total = Int(round(val * 60.0))
            }
        }
        // 3) Minutes suffix (e.g. 30m, 45 min, 15 minuten)
        else if let regex = try? NSRegularExpression(pattern: #"^(\d+)\s*(?:m|min|minuten)$"#, options: .caseInsensitive),
                let match = regex.firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)),
                let numRange = Range(match.range(at: 1), in: s),
                let mins = Int(s[numRange]) {
            total = mins
        }
        // 4) Hours suffix (e.g. 2h, 1.5 h, 1,5h, 2 stunden)
        else if let regex = try? NSRegularExpression(pattern: #"^(\d+(?:[.,]\d+)?)\s*(?:h|std|stunden)$"#, options: .caseInsensitive),
                let match = regex.firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)),
                let numRange = Range(match.range(at: 1), in: s) {
            let normalized = s[numRange].replacingOccurrences(of: ",", with: ".")
            if let val = Double(normalized) {
                total = Int(round(val * 60.0))
            }
        }

        guard let minutes = total else {
            throw SchichtaError("Dauer als 1:30, 1,5 oder 30m eingeben.", en: "Enter the duration as 1:30, 1.5 or 30m.")
        }

        guard minutes >= 1 && minutes <= 1440 else {
            throw SchichtaError("Dauer muss zwischen einer Minute und 24 Stunden liegen.", en: "Duration must be between one minute and 24 hours.")
        }

        return minutes
    }

    /// A signed hour amount such as "+12:30", "-4:00", "−1,5" or "20" (hours), for balances beyond 24 hours.
    static func parseSignedHours(_ input: String) -> Int? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "−", with: "-")
        guard !s.isEmpty else { return nil }
        var sign = 1
        if s.hasPrefix("-") { sign = -1; s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("h") { s.removeLast() }
        if s.range(of: #"^\d{1,4}:[0-5]\d$"#, options: .regularExpression) != nil {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            return sign * (parts[0] * 60 + parts[1])
        }
        if s.range(of: #"^\d{1,4}([.,]\d{1,2})?$"#, options: .regularExpression) != nil,
           let hours = Double(s.replacingOccurrences(of: ",", with: ".")) {
            return sign * Int((hours * 60).rounded())
        }
        return nil
    }

    /// "+1:30" / "−2:00" (true minus sign), for balances.
    static func formatSignedTime(_ minutes: Int) -> String {
        (minutes < 0 ? "−" : "+") + formatTime(abs(minutes))
    }

    /// Rounds a duration to the nearest multiple of `step` (halves round up): at least one step, at most 24 hours.
    static func snapDuration(_ minutes: Int, step: Int) -> Int {
        let step = max(1, step)
        let snapped = (max(0, minutes) + step / 2) / step * step
        return max(step, min(1440 / step * step, snapped))
    }

    /// Short label for duration buttons: "15m", "1h", "1,5h", "1:20".
    static func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        if minutes % 30 == 0 { return "\(minutes / 60),5h" }
        return formatTime(minutes)
    }

    static func formatTime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%02d:%02d", h, m)
    }

    static func formatGermanDate(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    static func weekdayName(_ day: String, language: AppLanguage = .de) -> String {
        let time = AppTime.state
        return time.weekday[language]!.string(from: time.day.date(from: day) ?? Date())
    }

    static func formatFullDate(_ day: String, language: AppLanguage = .de) -> String {
        let time = AppTime.state
        guard let date = time.day.date(from: day) else { return day }
        return time.fullDate[language]!.string(from: date)
    }

    static func isValidDate(_ s: String) -> Bool {
        let day = AppTime.day
        guard s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let d = day.date(from: s) else { return false }
        return day.string(from: d) == s
    }

    /// The calendar day (YYYY-MM-DD) of `date` in the app's time zone.
    static func day(from date: Date = Date()) -> String {
        AppTime.day.string(from: date)
    }

    /// Midnight at the start of `day` in the app's time zone.
    static func date(fromDay day: String) -> Date {
        AppTime.day.date(from: day) ?? Date()
    }

    /// The day `offset` days before/after `day` (YYYY-MM-DD), DST-safe via the app calendar.
    static func addDays(_ offset: Int, to day: String) -> String {
        let start = date(fromDay: day)
        return self.day(from: AppTime.calendar.date(byAdding: .day, value: offset, to: start) ?? start)
    }

    static func bcsReport(day: String, entries: [Entry]) -> String {
        let total = entries.reduce(0) { $0 + $1.minutes }
        var parts: [String] = [
            "Datum: \(formatGermanDate(day))",
            "Gesamtzeit: \(formatTime(total))",
            ""
        ]
        for (index, entry) in entries.enumerated() {
            parts.append("\(index + 1). \(entry.description.trimmingCharacters(in: .whitespacesAndNewlines))")
            let ticketVal = entry.ticket.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("Ticket: \(ticketVal.isEmpty ? "Ohne Ticket" : ticketVal)")
            let estSuffix = entry.estimated ? " (Schätzung – prüfen)" : ""
            parts.append("Dauer: \(formatTime(entry.minutes))\(estSuffix)")
            parts.append("")
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolveProjectName(for entry: Entry, repos: [TrackedRepo]) -> String {
        let explicit = entry.project.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }

        let entryTicket = entry.ticket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !entryTicket.isEmpty {
            if let match = repos.first(where: {
                let defT = $0.defaultTicket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return !defT.isEmpty && defT == entryTicket
            }) {
                return match.displayLabel
            }
        }

        let descLower = entry.description.lowercased()
        for r in repos {
            let labelLower = r.displayLabel.lowercased()
            let folderLower = r.folderName.lowercased()
            let folderSpace = folderLower.replacingOccurrences(of: "-", with: " ")
            if descLower.hasPrefix("\(labelLower):") || descLower.hasPrefix("\(folderLower):") || descLower.hasPrefix("\(folderSpace):") || descLower.contains("[\(labelLower)]") {
                return r.displayLabel
            }
        }
        for r in repos {
            let labelLower = r.displayLabel.lowercased()
            let folderLower = r.folderName.lowercased()
            let folderSpace = folderLower.replacingOccurrences(of: "-", with: " ")
            if (!labelLower.isEmpty && descLower.contains(labelLower)) ||
               (!folderLower.isEmpty && descLower.contains(folderLower)) ||
               (!folderSpace.isEmpty && descLower.contains(folderSpace)) {
                return r.displayLabel
            }
        }
        return ""
    }

    static func buildHookPayload(
        day: String,
        entries: [Entry],
        repos: [TrackedRepo],
        author: String,
        event: String = "day_booked"
    ) -> HookPayload {
        let totalMinutes = entries.reduce(0) { $0 + $1.minutes }
        return HookPayload(
            event: event,
            date: day,
            dateFormatted: formatGermanDate(day),
            author: author,
            totalMinutes: totalMinutes,
            totalFormatted: formatTime(totalMinutes),
            bcsReport: bcsReport(day: day, entries: entries),
            repositories: repos.map { r in
                HookPayload.Repository(folder: r.folderName, projectName: r.projectName, displayLabel: r.displayLabel,
                                       defaultTicket: r.defaultTicket, path: r.path, enabled: r.enabled)
            },
            entries: entries.map { e in
                HookPayload.Entry(id: e.id, date: e.date, projectName: resolveProjectName(for: e, repos: repos), ticket: e.ticket,
                                  description: e.description, minutes: e.minutes, durationFormatted: formatTime(e.minutes), estimated: e.estimated)
            }
        )
    }

    static func appendCheckIn(existingNotes: String, timeStr: String, text: String, ticket: String = "", minutes: Int = 30) throws -> String {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            throw SchichtaError("Bitte eine Tätigkeit oder Notiz eingeben.", en: "Please enter an activity or note.")
        }
        let cleanTicket = ticket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let prefix = cleanTicket.isEmpty ? "" : "[\(cleanTicket)] "
        let line = "- \(timeStr) (\(minutes) Min.): \(prefix)\(cleanText)"
        let base = existingNotes.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        return base.isEmpty ? line : "\(base)\n\(line)"
    }

    static func validate(database: Database) throws -> Database {
        guard database.version <= 1 else {
            throw SchichtaError(
                "Die Daten stammen von einer neueren Schichta-Version (Format \(database.version)). Bitte Schichta aktualisieren.",
                en: "The data comes from a newer Schichta version (format \(database.version)). Please update Schichta.")
        }
        guard database.version == 1 else {
            throw SchichtaError("Keine gültige Schichta-Sicherung.", en: "Not a valid Schichta backup.")
        }
        guard database.entries.count <= 50000 else {
            throw SchichtaError("Zu viele Einträge in der Sicherung.", en: "Too many entries in the backup.")
        }

        var ids = Set<String>()
        for e in database.entries {
            guard !ids.contains(e.id) else {
                throw SchichtaError("Doppelte Eintrags-ID in der Sicherung.", en: "Duplicate entry ID in the backup.")
            }
            ids.insert(e.id)
            guard isValidDate(e.date) else {
                throw SchichtaError("Ungültiges Eintragsdatum: \(e.date)", en: "Invalid entry date: \(e.date)")
            }
            guard e.minutes >= 1 && e.minutes <= 1440 else {
                throw SchichtaError("Dauer außerhalb des gültigen Bereichs (1-1440 Min).", en: "Duration out of range (1–1440 min).")
            }
            guard e.ticket.count <= 100 else {
                throw SchichtaError("Ticketname zu lang.", en: "Ticket name too long.")
            }
            let desc = e.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !desc.isEmpty && desc.count <= 4000 else {
                throw SchichtaError("Ungültige Tätigkeitsbeschreibung.", en: "Invalid activity description.")
            }
        }

        for (day, item) in database.journal {
            guard isValidDate(day) else {
                throw SchichtaError("Ungültiges Notizdatum: \(day)", en: "Invalid note date: \(day)")
            }
            guard item.notes.count <= 200000 && item.logs.count <= 200000 && item.answer.count <= 200000 else {
                throw SchichtaError("Notizinhalt zu lang.", en: "Note content too long.")
            }
        }

        return database
    }
}

/// The JSON that shell hooks get on stdin and webhooks get as the body. External scripts depend on these
/// field names: add fields freely, but never rename or remove one (HookPayloadTests pins the format).
struct HookPayload: Codable, Equatable {
    struct Repository: Codable, Equatable {
        let folder: String
        let projectName: String
        let displayLabel: String
        let defaultTicket: String
        let path: String
        let enabled: Bool
    }

    struct Entry: Codable, Equatable {
        let id: String
        let date: String
        let projectName: String
        let ticket: String
        let description: String
        let minutes: Int
        let durationFormatted: String
        let estimated: Bool
    }

    let event: String
    let date: String
    let dateFormatted: String
    let author: String
    let totalMinutes: Int
    let totalFormatted: String
    let bcsReport: String
    let repositories: [Repository]
    let entries: [Entry]

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
