import AppKit
import UniformTypeIdentifiers

extension SchichtaStore {
    // --- Import / Export ---

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Shows the panel as a sheet on the window (if any), otherwise modally, and calls `onURL` only on "OK".
    func present(_ panel: NSSavePanel, window: NSWindow?, onURL: @escaping (URL) throws -> Void, failure: @escaping (Error) -> String) {
        let handler: (NSApplication.ModalResponse) -> Void = { result in
            guard result == .OK, let url = panel.url else { return }
            do { try onURL(url) } catch { self.showToast(failure(error)) }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    func copyBCSReport() {
        copyToPasteboard(SchichtaCore.bcsReport(day: selectedDay, entries: entriesForSelectedDay()))
        showToast(t("importExport.dailyDraftCopiedToClipboard"))
    }

    func copyBCSReportAndMarkBooked(day: String? = nil) {
        let targetDay = day ?? selectedDay
        copyToPasteboard(SchichtaCore.bcsReport(day: targetDay, entries: database.entries.filter { $0.date == targetDay }))
        markDayBooked(targetDay, booked: true)
        showToast(t("importExport.dailyDraftCopiedDayMarked"))
    }

    func saveBCSReportToFile(window: NSWindow?) {
        let rep = SchichtaCore.bcsReport(day: selectedDay, entries: entriesForSelectedDay())
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tagesentwurf-\(selectedDay).txt"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        present(panel, window: window, onURL: { url in
            try Data(rep.utf8).write(to: url, options: .atomic)
            self.showToast(self.t("importExport.dailyDraftSaved"))
        }, failure: { self.t("importExport.errorSaving", "\($0.localizedDescription)") })
    }

    func exportBackup(window: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Schichta-Sicherung-\(SchichtaCore.day()).json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        present(panel, window: window, onURL: { url in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self.database).write(to: url, options: .atomic)
            self.showToast(self.t("importExport.backupSuccessfullyExported"))
        }, failure: { self.t("importExport.exportFailed", "\($0.localizedDescription)") })
    }

    func importBackup(window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        present(panel, window: window, onURL: { url in
            let data = try Data(contentsOf: url)
            guard data.count <= 10_000_000 else {
                self.showToast(self.t("importExport.fileIsTooLargeMaximum"))
                return
            }
            let validated = try SchichtaCore.validate(database: JSONDecoder().decode(Database.self, from: data))
            self.database = validated
            self.save()
            self.showToast(self.t("importExport.entriesImported", "\(validated.entries.count)"))
        }, failure: { self.t("importExport.importFailed", "\($0.localizedDescription)") })
    }
}
