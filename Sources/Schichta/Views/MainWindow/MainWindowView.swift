import AppKit
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var store: SchichtaStore

    // Form states
    @State var formTicket: String = ""
    @State var formDuration: String = "0:15"
    @State var formDescription: String = ""
    @State var formEstimated: Bool = false
    @State var editingEntryId: String? = nil

    // Date Picker Popover state
    @State var showDatePickerPopover: Bool = false
    @State var showTargetsSheet: Bool = false
    @State var showAISheet: Bool = false

    // Confirmations
    @State var entryToDelete: Entry? = nil
    @State var showDeleteAlert: Bool = false

    // Notes disclosure
    @State var isNotesExpanded: Bool = false
    @State var notesText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Custom macOS Header Bar (replaces native toolbar)
            customHeaderBar

            // Toast Banner
            if let toast = store.toastMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(SchichtaTheme.forestGreen)
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Prompt Banners (Morgen- / Feierabend-Abschluss)
            if case .morning(let unbookedDay) = store.activePrompt {
                morningPromptBanner(unbookedDay: unbookedDay)
            }
            if case .endOfDay(let day) = store.activePrompt {
                endOfDayPromptBanner(day: day)
            }

            // Top Status Metrics Bar (4 Tiles)
            topMetricsBar
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            // Main Two-Column View
            HSplitView {
                // Left Column: Scrollable Task Management
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 1. Quick Entry Form
                        entryFormCard

                        // 2. Recognized Proposals (if any)
                        if !store.proposals.isEmpty || store.isSynthesizing || hasAISummaryForDay {
                            proposalsCard
                        }

                        // 3. Today's Entries
                        entriesListCard

                        // 4. Daily Notes
                        notesCard
                    }
                    .padding(20)
                }
                .frame(minWidth: 500)

                // Right Column: Inspector (BCS Report)
                inspectorColumn
                    .frame(width: 350)
            }
        }
        .frame(minWidth: 950, minHeight: 650)
        .onAppear {
            self.notesText = store.journalForSelectedDay().notes
        }
        .onChange(of: store.selectedDay) {
            self.notesText = store.journalForSelectedDay().notes
            self.resetForm()
        }
        .sheet(isPresented: $showAISheet) {
            AISummarySheet(store: store, isPresented: $showAISheet)
        }
        .sheet(isPresented: $showTargetsSheet) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox(label: Label(store.t("Shell-Hook / Adapter", "Shell hook / adapter"), systemImage: "terminal")) {
                            VStack(alignment: .leading, spacing: 8) {
                                if store.hasExternalHookConfigured {
                                    Button(action: { store.runExternalHook(for: store.selectedDay) }) {
                                        Label(store.t("Für \(SchichtaCore.formatGermanDate(store.selectedDay)) ausführen", "Run for \(SchichtaCore.formatGermanDate(store.selectedDay))"), systemImage: "play.fill")
                                    }
                                    if !store.lastHookResult.isEmpty {
                                        Text(store.lastHookResult)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                } else {
                                    Button(store.t("Kein Hook eingerichtet – Einstellungen öffnen…", "No hook set up – open settings…")) {
                                        showTargetsSheet = false
                                        appDelegate()?.showSettings(tab: 3)
                                    }
                                    .buttonStyle(.link)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        BookingTargetsSection(store: store)
                    }
                    .padding(20)
                }
                Divider()
                HStack {
                    Spacer()
                    Button(store.t("Fertig", "Done")) { showTargetsSheet = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 680, height: 540)
        }
        .alert(store.t("Eintrag löschen?", "Delete entry?"), isPresented: $showDeleteAlert, presenting: entryToDelete) { entry in
            Button(store.t("Abbrechen", "Cancel"), role: .cancel) { }
            Button(store.t("Löschen", "Delete"), role: .destructive) {
                store.deleteEntry(id: entry.id)
                if editingEntryId == entry.id { resetForm() }
            }
        } message: { entry in
            Text(store.t("Möchtest du „\(entry.description)“ wirklich löschen?", "Do you really want to delete „\(entry.description)“?"))
        }
    }

    // MARK: - Form Helper

    func addMinutesToDuration(_ mins: Int) {
        if let current = try? SchichtaCore.parseMinutes(formDuration) {
            formDuration = SchichtaCore.formatTime(SchichtaCore.clampDuration(current + mins))
        } else {
            formDuration = SchichtaCore.formatTime(max(5, mins))
        }
    }

    func startEditing(_ entry: Entry) {
        editingEntryId = entry.id
        formTicket = entry.ticket
        formDuration = SchichtaCore.formatTime(entry.minutes)
        formDescription = entry.description
        formEstimated = entry.estimated
    }

    func resetForm() {
        editingEntryId = nil
        formTicket = ""
        formDuration = "0:15"
        formDescription = ""
        formEstimated = false
    }

    func saveForm() {
        let trimmedDesc = formDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDesc.isEmpty else {
            store.showToast(store.t("Bitte Beschreibung eingeben.", "Please enter a description."))
            return
        }

        guard let minutes = try? SchichtaCore.parseMinutes(formDuration) else {
            store.showToast(store.t("Ungültige Dauer. Bitte als 0:30, 1,5 oder 30m eingeben.", "Invalid duration. Please enter as 0:30, 1.5 or 30m."))
            return
        }

        if let editId = editingEntryId {
            store.updateEntry(id: editId, ticket: formTicket, description: trimmedDesc, minutes: minutes, estimated: formEstimated)
        } else {
            store.addEntry(ticket: formTicket, description: trimmedDesc, minutes: minutes, estimated: formEstimated)
        }

        resetForm()
    }
}
