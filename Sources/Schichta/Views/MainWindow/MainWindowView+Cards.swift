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
            title: editingEntryId != nil ? store.t("main.editActivity") : store.t("main.addActivity"),
            icon: "plus.circle.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: ticket + duration side by side
                HStack(alignment: .center, spacing: 12) {
                    // Ticket Input
                    HStack(spacing: 4) {
                        TextField(store.t("main.ticketOptionalExampleProj2800"), text: $formTicket)
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
                        Text(store.t("main.duration"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .fixedSize()

                        StepButton(increase: false, size: 15, help: store.t("main.minutes", "\(store.timeStepMinutes)")) { addStepsToDuration(-1) }

                        DurationInput(text: $formDuration, step: store.timeStepMinutes)

                        StepButton(increase: true, size: 15, help: store.t("main.minutes2", "\(store.timeStepMinutes)")) { addStepsToDuration(1) }

                        HStack(spacing: 3) {
                            ForEach(store.durationPresets, id: \.self) { minutes in
                                Button(SchichtaCore.durationLabel(minutes)) { formDuration = SchichtaCore.formatTime(minutes) }
                            }
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
                        Text(store.t("main.recent"))
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
                TextField(store.t("main.whatDidYouWorkOn"), text: $formDescription)
                    .textFieldStyle(.roundedBorder)

                // Row 3: footer with checkbox + save button
                HStack {
                    Toggle(store.t("main.timeIsEstimatedVerifyBefore"), isOn: $formEstimated)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))

                    Spacer()

                    if editingEntryId != nil {
                        Button(store.t("main.cancel")) {
                            resetForm()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                    }

                    Button(editingEntryId != nil ? store.t("main.saveChanges") : store.t("main.saveEntry")) {
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
                Label(store.t("main.aiSummary"), systemImage: "wand.and.stars")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Button(store.t("main.addToDailyNotes")) {
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
            title: store.t("main.automaticallyRecognizedActivities", "\(store.proposals.count)"),
            icon: "sparkles",
            trailing: {
                if !store.proposals.isEmpty {
                    Button(store.t("main.acceptAllWithDuration")) {
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
                        Text(store.t("main.analyzingGitCommitsReflogsAnd"))
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
                    }, language: store.appLanguage, step: store.timeStepMinutes)
                }
            }
        }
    }

    var entriesListCard: some View {
        let entries = store.entriesForSelectedDay()

        return sectionCard(
            title: store.t("main.yourEntriesOn", "\(SchichtaCore.formatGermanDate(store.selectedDay))"),
            icon: "checklist",
            trailing: {
                Text(entries.count == 1 ? store.t("main.1Entry") : store.t("main.entries", "\(entries.count)"))
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
                        Text(store.t("main.noEntriesForThisDay"))
                            .font(.system(size: 13, weight: .medium))
                        Text(store.t("main.addAnActivityAboveOr"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        if let source = store.lastDayWithEntries(before: store.selectedDay) {
                            Button {
                                store.copyEntries(from: source)
                            } label: {
                                Label(store.t("main.copyEntriesFrom", "\(SchichtaCore.formatGermanDate(source))"), systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 4)
                            .help(store.t("main.copyEntriesFromHelp"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .center, spacing: 10) {
                            // Ticket Badge
                            if entry.ticket.isEmpty {
                                Text(store.t("main.noTicket"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .fixedSize()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(nsColor: .controlColor))
                                    .cornerRadius(4)
                            } else {
                                Text(entry.ticket)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .fixedSize()
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(SchichtaTheme.forestGreen)
                                    .cornerRadius(4)
                            }
                            CopyButton(text: entry.ticket, help: store.t("main.copyTicket"), store: store)

                            // Project label and description: the label only when the description still keeps
                            // 110 pt, so a narrow window neither breaks words nor pushes the buttons off the row.
                            let proj = !entry.project.isEmpty ? entry.project : SchichtaCore.resolveProjectName(for: entry, repos: store.trackedRepos)
                            let description = Text(entry.description.isEmpty ? store.t("main.noDescription") : entry.description)
                                .font(.system(size: 13))
                                .foregroundColor(entry.description.isEmpty ? .secondary : .primary)
                                .lineLimit(2)
                                .frame(minWidth: 110, idealWidth: 110, maxWidth: .infinity, alignment: .leading)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    if !proj.isEmpty {
                                        Text(proj)
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .fixedSize()
                                            .foregroundColor(SchichtaTheme.forestGreen)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2.5)
                                            .background(SchichtaTheme.forestGreen.opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                    description
                                }
                                description
                            }
                            .help(proj)
                            CopyButton(text: entry.description, help: store.t("main.copyDescription"), store: store)

                            // Estimated Tag / Confirm Button
                            if entry.estimated {
                                Button(action: { store.confirmEstimate(id: entry.id) }) {
                                    HStack(spacing: 3) {
                                        Text(store.t("main.estimated"))
                                            .fixedSize() // never break the word in a narrow window
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
                                .help(store.t("main.clickToConfirmEstimate"))
                            }

                            // One step less
                            StepButton(increase: false, size: 15, help: store.t("main.minutes", "\(store.timeStepMinutes)")) {
                                store.adjustEntryMinutes(id: entry.id, steps: -1)
                            }

                            // Inline Duration Field
                            InlineDurationField(entry: entry, store: store)

                            // One step more
                            StepButton(increase: true, size: 15, help: store.t("main.minutes2", "\(store.timeStepMinutes)")) {
                                store.adjustEntryMinutes(id: entry.id, steps: 1)
                            }

                            // Two steps more
                            Button("+" + SchichtaCore.durationLabel(2 * store.timeStepMinutes)) {
                                store.adjustEntryMinutes(id: entry.id, steps: 2)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                            .fixedSize()
                            .help(store.t("main.addMinutes", "\(2 * store.timeStepMinutes)"))

                            CopyButton(text: SchichtaCore.formatTime(entry.minutes), help: store.t("main.copyDuration"), store: store)

                            // Edit & Delete
                            Button(action: { startEditing(entry) }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(store.t("main.edit"))

                            Button(action: {
                                entryToDelete = entry
                                showDeleteAlert = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                            .help(store.t("main.delete"))
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
            title: store.t("main.dailyNotes"),
            icon: "note.text",
            trailing: {
                Button(action: {
                    store.openSettings(tab: .gitRepos)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(store.t("main.inspectGitActivitiesInSettings"))
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundColor(SchichtaTheme.forestGreen)
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("main.freeDailyNotes30mCheck"))
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
