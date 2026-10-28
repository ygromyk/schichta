import AppKit
import UniformTypeIdentifiers

extension SchichtaStore {
    /// First and last day (YYYY-MM-DD) of the month containing `day`.
    static func monthBounds(of day: String) -> (start: String, end: String) {
        let start = String(day.prefix(8)) + "01"
        let nextMonth = AppTime.calendar.date(byAdding: .month, value: 1, to: SchichtaCore.date(fromDay: start)) ?? Date()
        return (start, SchichtaCore.addDays(-1, to: SchichtaCore.day(from: nextMonth)))
    }

    /// One row per entry, plus a row for each day off, for the month containing `day`.
    /// German uses ";" and decimal commas (what Excel expects there), English "," and dots.
    func monthCSV(containing day: String) -> String {
        let (start, end) = Self.monthBounds(of: day)
        let isDe = appLanguage == .de
        let separator = isDe ? ";" : ","
        func cell(_ value: String) -> String {
            var text = value
            // Spreadsheets run cells starting like a formula: keep them text (CSV injection).
            if let first = text.first, "=+-@".contains(first) { text = "'" + text }
            if text.contains(separator) || text.contains("\"") || text.contains("\n") {
                text = "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return text
        }
        func hours(_ minutes: Int) -> String {
            let value = String(format: "%.2f", Double(minutes) / 60)
            return isDe ? value.replacingOccurrences(of: ".", with: ",") : value
        }

        let header = ["date", "weekday", "ticket", "project", "description", "minutes", "hours", "estimated", "booked", "absence"]
            .map { t("export.column.\($0)") }
        var rows = [header.joined(separator: separator)]
        let yes = t("export.yes"), no = t("export.no")

        var current = start
        while current <= end {
            let weekday = SchichtaCore.weekdayName(current, language: appLanguage)
            let booked = database.journal[current]?.booked == true ? yes : no
            let absence = self.absence(on: current)?.title(for: appLanguage) ?? ""
            let entries = database.entries.filter { $0.date == current }
            for entry in entries {
                rows.append([
                    current, weekday, entry.ticket, SchichtaCore.resolveProjectName(for: entry, repos: trackedRepos), entry.description,
                    "\(entry.minutes)", hours(entry.minutes), entry.estimated ? yes : no, booked, absence,
                ].map(cell).joined(separator: separator))
            }
            if entries.isEmpty, !absence.isEmpty {
                rows.append([current, weekday, "", "", absence, "0", hours(0), no, booked, absence].map(cell).joined(separator: separator))
            }
            current = SchichtaCore.addDays(1, to: current)
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    func exportMonthCSV(window: NSWindow?) {
        let (start, _) = Self.monthBounds(of: selectedDay)
        let csv = monthCSV(containing: selectedDay)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Schichta-\(start.prefix(7)).csv"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.commaSeparatedText]
        present(panel, window: window, onURL: { url in
            // The byte order mark makes Excel read the file as UTF-8 (umlauts).
            try Data(("\u{FEFF}" + csv).utf8).write(to: url, options: .atomic)
            self.showToast(self.t("export.monthExported", "\(url.lastPathComponent)"))
        }, failure: { self.t("export.exportFailed", "\(self.describe($0))") })
    }
}
