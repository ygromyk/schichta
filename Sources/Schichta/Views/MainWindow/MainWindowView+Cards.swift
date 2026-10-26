import AppKit
import SwiftUI

extension MainWindowView {
    // MARK: - Harmonized Section Card Component

    @ViewBuilder
    func sectionCard<Trailing: View, Content: View>(
        title: String,
        icon: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Card Header
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SchichtaTheme.forestGreen)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                trailing()
            }

            // Card Content
            content()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        sectionCard(title: title, icon: icon, trailing: { EmptyView() }, content: content)
    }

    // MARK: - Left Column Cards

    var entryFormCard: some View {
        sectionCard(
            title: editingEntryId != nil ? store.t("Eintrag bearbeiten", "Edit activity") : store.t("Tätigkeit erfassen", "Add activity"),
            icon: "plus.circle.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: ticket + duration side by side
                HStack(alignment: .center, spacing: 12) {
                    // Ticket Input
                    HStack(spacing: 4) {
                        TextField(store.t("Ticket optional (z. B. PROJ-2800)", "Ticket optional (e.g. PROJ-2800)"), text: $formTicket)
                            .textFieldStyle(.roundedBorder)

                        if !formTicket.isEmpty {
                            Button(action: { formTicket = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Duration stepper & quick buttons
                    HStack(spacing: 5) {
                        Text(store.t("Dauer:", "Duration:"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .fixedSize()

                        StepButton(increase: false, size: 15, help: store.t("−15 Minuten (mind. 5 Min.)", "−15 minutes (min. 5 min.)")) { addMinutesToDuration(-15) }

                        TextField("0:15", text: $formDuration)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(width: 58)

                        StepButton(increase: true, size: 15, help: store.t("+15 Minuten", "+15 minutes")) { addMinutesToDuration(15) }

                        HStack(spacing: 3) {
                            Button("15m") { formDuration = "00:15" }
                            Button("30m") { formDuration = "00:30" }
                            Button("45m") { formDuration = "00:45" }
                            Button("1h") { formDuration = "01:00" }
                            Button("1,5h") { formDuration = "01:30" }
                            Button("2h") { formDuration = "02:00" }
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .fixedSize()
                    }
                }

                // Recent tickets (if any)
                let recents = store.recentTickets()
                if !recents.isEmpty {
                    HStack(spacing: 5) {
                        Text(store.t("Zuletzt:", "Recent:"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(recents, id: \.self) { t in
                                    Button(t) {
                                        formTicket = t
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: .controlColor))
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }
                }

                // Row 2: description field
                TextField(store.t("Woran hast du gearbeitet? (z. B. Abstimmung Architektur)", "What did you work on? (e.g. Architecture sync)"), text: $formDescription)
                    .textFieldStyle(.roundedBorder)

                // Row 3: footer with checkbox + save button
                HStack {
                    Toggle(store.t("Zeit ist geschätzt (vor Buchung prüfen)", "Time is estimated (verify before booking)"), isOn: $formEstimated)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))

                    Spacer()

                    if editingEntryId != nil {
                        Button(store.t("Abbrechen", "Cancel")) {
                            resetForm()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                    }

                    Button(editingEntryId != nil ? store.t("Änderungen speichern", "Save changes") : store.t("Eintrag speichern", "Save entry")) {
                        saveForm()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SchichtaTheme.forestGreen)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
    }

    var hasAISummaryForDay: Bool {
        store.aiSummaryDay == store.selectedDay && !(store.aiSummaryText.isEmpty && store.aiQuestions.isEmpty)
    }

    var aiSummaryBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(store.t("KI-Zusammenfassung", "AI summary"), systemImage: "wand.and.stars")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Button(store.t("In Tagesnotizen übernehmen", "Add to daily notes")) {
                    let current = store.journalForSelectedDay().notes
                    let addition = "KI-Zusammenfassung: " + store.aiSummaryText
                    notesText = current.isEmpty ? addition : current + "\n\n" + addition
                    store.updateJournalNotes(notesText)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .disabled(store.aiSummaryText.isEmpty)
            }
            if !store.aiSummaryText.isEmpty {
                Text(store.aiSummaryText)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(store.aiQuestions, id: \.self) { question in
                Label(question, systemImage: "questionmark.circle")
                    .font(.system(size: 11.5))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SchichtaTheme.forestGreen.opacity(0.08))
        .cornerRadius(8)
    }

    var proposalsCard: some View {
        sectionCard(
            title: store.t("Automatisch erkannte Tätigkeiten (\(store.proposals.count))", "Automatically recognized activities (\(store.proposals.count))"),
            icon: "sparkles",
            trailing: {
                if !store.proposals.isEmpty {
                    Button(store.t("Alle mit Zeit übernehmen", "Accept all with duration")) {
                        store.acceptAllProposals()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SchichtaTheme.forestGreen)
                    .controlSize(.small)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if store.isSynthesizing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(store.t("Git-Commits, Reflogs und Notizen werden analysiert...", "Analyzing Git commits, reflogs and notes..."))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if hasAISummaryForDay {
                    aiSummaryBox
                }

                ForEach(store.proposals) { prop in
                    ProposalRowView(proposal: prop, onAccept: { p in
                        store.acceptProposal(p)
                    }, language: store.appLanguage)
                }
            }
        }
    }

    var entriesListCard: some View {
        let entries = store.entriesForSelectedDay()

        return sectionCard(
            title: store.t("Deine Einträge am \(SchichtaCore.formatGermanDate(store.selectedDay))", "Your entries on \(SchichtaCore.formatGermanDate(store.selectedDay))"),
            icon: "checklist",
            trailing: {
                Text(entries.count == 1 ? store.t("1 Eintrag", "1 entry") : store.t("\(entries.count) Einträge", "\(entries.count) entries"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if entries.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text(store.t("Noch keine Einträge für diesen Tag.", "No entries for this day yet."))
                            .font(.system(size: 13, weight: .medium))
                        Text(store.t("Erfasse eine Tätigkeit oben oder nutze die automatische Auswertung.", "Add an activity above or use automatic analysis."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .center, spacing: 10) {
                            // Ticket Badge
                            if entry.ticket.isEmpty {
                                Text(store.t("Ohne Ticket", "No ticket"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(nsColor: .controlColor))
                                    .cornerRadius(4)
                            } else {
                                Text(entry.ticket)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(SchichtaTheme.forestGreen)
                                    .cornerRadius(4)
                            }

                            // Project Badge (if matched)
                            let proj = !entry.project.isEmpty ? entry.project : SchichtaCore.resolveProjectName(for: entry, repos: store.trackedRepos)
                            if !proj.isEmpty {
                                Text(proj)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(SchichtaTheme.forestGreen)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(SchichtaTheme.forestGreen.opacity(0.12))
                                    .cornerRadius(4)
                            }

                            // Description
                            Text(entry.description)
                                .font(.system(size: 13))
                                .lineLimit(2)

                            Spacer()

                            // Estimated Tag / Confirm Button
                            if entry.estimated {
                                Button(action: { store.confirmEstimate(id: entry.id) }) {
                                    HStack(spacing: 3) {
                                        Text(store.t("Geschätzt", "Estimated"))
                                        Image(systemName: "checkmark")
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .help(store.t("Klicken um Schätzung als bestätigt zu markieren", "Click to confirm estimate"))
                            }

                            // Quick −15m
                            StepButton(increase: false, size: 15, help: store.t("−15 Minuten (mind. 5 Min.)", "−15 minutes (min. 5 min.)")) {
                                store.adjustEntryMinutes(id: entry.id, delta: -15)
                            }

                            // Inline Duration Field
                            InlineDurationField(entry: entry, store: store)

                            // Quick +15m
                            StepButton(increase: true, size: 15, help: store.t("+15 Minuten", "+15 minutes")) {
                                store.adjustEntryMinutes(id: entry.id, delta: 15)
                            }

                            // Quick +30m
                            Button("+30m") {
                                store.adjustEntryMinutes(id: entry.id, delta: 30)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                            .help(store.t("+30 Minuten hinzufügen", "+30 minutes add"))

                            // Edit & Delete
                            Button(action: { startEditing(entry) }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(store.t("Bearbeiten", "Edit"))

                            Button(action: {
                                entryToDelete = entry
                                showDeleteAlert = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                            .help(store.t("Löschen", "Delete"))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(editingEntryId == entry.id ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                    }
                }
            }
        }
    }

    var notesCard: some View {
        sectionCard(
            title: store.t("Tagesnotizen", "Daily Notes"),
            icon: "note.text",
            trailing: {
                Button(action: {
                    store.openSettings(tab: 2)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(store.t("Git-Aktivitäten in den Einstellungen prüfen…", "Inspect Git activities in Settings…"))
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundColor(SchichtaTheme.forestGreen)
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("Freie Tagesnotizen & 30m Check-in Protokoll:", "Free daily notes & 30m check-in log:"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                TextEditor(text: $notesText)
                    .font(.system(size: 12))
                    .frame(minHeight: 120)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .onChange(of: notesText) {
                        store.updateJournalNotes(notesText)
                    }
            }
        }
    }
}
