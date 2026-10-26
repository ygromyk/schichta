import AppKit

extension SchichtaStore {
    // --- Date Navigation ---

    func selectDay(_ day: String) {
        guard SchichtaCore.isValidDate(day) else { return }
        self.selectedDay = day
        self.selectedDate = SchichtaCore.date(fromDay: day)
        self.proposals.removeAll()
    }

    func selectDate(_ date: Date) {
        let day = SchichtaCore.day(from: date)
        selectDay(day)
    }

    func moveDay(_ offset: Int) {
        selectDay(SchichtaCore.addDays(offset, to: selectedDay))
    }

    func selectToday() {
        selectDate(Date())
    }

    // --- Queries ---

    func entriesForSelectedDay() -> [Entry] {
        database.entries.filter { $0.date == selectedDay }
    }

    func journalForSelectedDay() -> JournalItem {
        database.journal[selectedDay] ?? JournalItem()
    }

    func recentTickets() -> [String] {
        var seen = Set<String>()
        var list: [String] = []
        for e in database.entries.reversed() {
            let t = e.ticket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !t.isEmpty && t != "PROJ-0" && !seen.contains(t) {
                seen.insert(t)
                list.append(t)
                if list.count >= 6 { break }
            }
        }
        return list
    }

    // --- CRUD Entries ---

    func addEntry(ticket: String, description: String, minutes: Int, estimated: Bool, project: String = "") {
        let cleanTicket = ticket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDesc.isEmpty else { return }

        let daySum = entriesForSelectedDay().reduce(0) { $0 + $1.minutes }
        if daySum + minutes > 1440 {
            showToast(t("Fehler: Tagessumme darf 24 Stunden nicht überschreiten.", "Error: Daily total cannot exceed 24 hours."))
            return
        }

        var newEntry = Entry(date: selectedDay, ticket: cleanTicket, description: cleanDesc, minutes: minutes, estimated: estimated, project: project)
        newEntry.project = SchichtaCore.resolveProjectName(for: newEntry, repos: trackedRepos)
        database.entries.append(newEntry)
        save()
        showToast(t("Eintrag hinzugefügt.", "Entry added."))
    }

    func updateEntry(id: String, ticket: String, description: String, minutes: Int, estimated: Bool, project: String? = nil) {
        guard let idx = database.entries.firstIndex(where: { $0.id == id }) else { return }
        let cleanTicket = ticket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDesc.isEmpty else { return }

        database.entries[idx].ticket = cleanTicket
        database.entries[idx].description = cleanDesc
        database.entries[idx].minutes = minutes
        database.entries[idx].estimated = estimated
        if let p = project {
            database.entries[idx].project = p
        }
        save()
        showToast(t("Eintrag aktualisiert.", "Entry updated."))
    }

    func deleteEntry(id: String) {
        database.entries.removeAll(where: { $0.id == id })
        save()
        showToast(t("Eintrag gelöscht.", "Entry deleted."))
    }

    func confirmEstimate(id: String) {
        guard let idx = database.entries.firstIndex(where: { $0.id == id }) else { return }
        database.entries[idx].estimated = false
        save()
        showToast(t("Schätzung bestätigt.", "Estimate confirmed."))
    }

    func adjustEntryMinutes(id: String, delta: Int) {
        guard let idx = database.entries.firstIndex(where: { $0.id == id }) else { return }
        let current = database.entries[idx].minutes
        let updated = SchichtaCore.clampDuration(current + delta)
        guard updated != current else { return }
        database.entries[idx].minutes = updated
        save()
        let sign = delta >= 0 ? "+\(delta)" : "\(delta)"
        showToast(t("Dauer angepasst (\(sign) Min.): \(SchichtaCore.formatTime(updated))", "Duration adjusted (\(sign) min): \(SchichtaCore.formatTime(updated))"))
    }

    func setEntryMinutes(id: String, minutes: Int) {
        guard let idx = database.entries.firstIndex(where: { $0.id == id }) else { return }
        let updated = SchichtaCore.clampDuration(minutes)
        guard updated != database.entries[idx].minutes else { return }
        database.entries[idx].minutes = updated
        save()
        showToast(t("Dauer geändert: \(SchichtaCore.formatTime(updated))", "Duration changed: \(SchichtaCore.formatTime(updated))"))
    }

    // --- Journal & Check-Ins ---

    func updateJournalNotes(_ notes: String) {
        var item = database.journal[selectedDay] ?? JournalItem()
        item.notes = notes
        database.journal[selectedDay] = item
        save()
    }

    func handleCheckIn(text: String, ticket: String, mode: CheckInMode, timeStr: String, minutes: Int = 30) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        let cleanTicket = ticket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let today = SchichtaCore.day()
        let effectiveMinutes = max(1, min(1440, minutes))

        if mode == .both {
            // Check if today already has an identical entry (same ticket and same text)
            if let idx = database.entries.firstIndex(where: {
                $0.date == today &&
                $0.ticket == cleanTicket &&
                $0.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == cleanText.lowercased()
            }) {
                let newMin = min(1440, database.entries[idx].minutes + effectiveMinutes)
                database.entries[idx].minutes = newMin
            } else {
                var entry = Entry(date: today, ticket: cleanTicket, description: cleanText, minutes: effectiveMinutes, estimated: true)
                entry.project = SchichtaCore.resolveProjectName(for: entry, repos: trackedRepos)
                database.entries.append(entry)
            }
        }

        // Always append to today's journal notes
        var item = database.journal[today] ?? JournalItem()
        if let updatedNotes = try? SchichtaCore.appendCheckIn(existingNotes: item.notes, timeStr: timeStr, text: cleanText, ticket: cleanTicket, minutes: effectiveMinutes) {
            item.notes = updatedNotes
            database.journal[today] = item
        }

        save()
        showToast(mode == .both ? t("\(effectiveMinutes)m-Eintrag & Notiz erfasst.", "\(effectiveMinutes)m entry & note recorded.") : t("Check-in als Notiz gespeichert.", "Check-in saved as note."))
    }

    // --- Auto Synthesize Actions ---

    func synthesizeDayAction() {
        isSynthesizing = true
        let day = selectedDay
        let existing = entriesForSelectedDay()
        loadGitActivity(for: day) { [weak self] outcome in
            guard let self = self else { return }
            self.isSynthesizing = false
            switch outcome {
            case .success(let loaded):
                let synth = AutoSynthesizer.synthesizeDay(day: day, journal: loaded.journal, gitResult: loaded.result, existingEntries: existing)
                self.proposals = synth
                self.showToast(self.t("\(synth.count) Tätigkeiten automatisch erkannt.", "\(synth.count) activities automatically recognized."))
            case .failure(let error):
                self.showToast(self.t("Fehler bei Git-Auswertung: \(error.localizedDescription)", "Git analysis error: \(error.localizedDescription)"))
            }
        }
    }

    func applyAISummary(_ result: AISummary.Result, day: String) {
        aiSummaryDay = day
        aiSummaryText = result.summary
        aiQuestions = result.questions
        // Frühere KI-Vorschläge ersetzen, lokale (Git/Check-in) behalten.
        proposals = proposals.filter { !$0.id.hasPrefix("ai-") } + result.proposals
        showToast(t("\(result.proposals.count) KI-Vorschläge – bitte prüfen.", "\(result.proposals.count) AI proposals – please review."))
    }

    func acceptProposal(_ prop: ProposedEntry) {
        guard prop.minutes > 0 else {
            showToast(t("Bitte zuerst eine Dauer eintragen.", "Please enter a duration first."))
            return
        }
        addEntry(ticket: prop.ticket, description: prop.description, minutes: prop.minutes, estimated: prop.estimated, project: prop.project)
        proposals.removeAll(where: { $0.id == prop.id })
    }

    func acceptAllProposals() {
        // Vorschläge ohne Dauer (z. B. KI „Zeit offen“) bleiben zur Bearbeitung stehen.
        for prop in proposals where prop.minutes > 0 {
            addEntry(ticket: prop.ticket, description: prop.description, minutes: prop.minutes, estimated: prop.estimated, project: prop.project)
        }
        proposals.removeAll(where: { $0.minutes > 0 })
        showToast(t("Alle Vorschläge übernommen.", "All proposals accepted."))
    }
}
