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
    @State var showWeekBooking: Bool = false

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

            if let problem = store.storeProblem {
                storeProblemBanner(problem)
            }

            // Prompt banners (morning / end of day)
            if case .morning(let unbookedDay) = store.activePrompt {
                morningPromptBanner(unbookedDay: unbookedDay)
            }
            if case .endOfDay(let day) = store.activePrompt {
                endOfDayPromptBanner(day: day)
            }

            if store.mainViewMode == .week {
                weekOverview
            } else {
                if let absence = store.absence(on: store.selectedDay) {
                    absenceBanner(absence, day: store.selectedDay)
                }
                dayView
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
        .sheet(isPresented: $showWeekBooking) {
            WeekBookingSheet(store: store, week: store.weekSummary(containing: store.selectedDay), isPresented: $showWeekBooking)
        }
        .sheet(isPresented: $showAISheet) {
            AISummarySheet(store: store, isPresented: $showAISheet)
        }
        .sheet(isPresented: $showTargetsSheet) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox(label: Label(store.t("main.shellHookAdapter"), systemImage: "terminal")) {
                            VStack(alignment: .leading, spacing: 8) {
                                if store.hasExternalHookConfigured {
                                    Button(action: { store.runExternalHook(for: store.selectedDay) }) {
                                        Label(store.t("main.runFor", "\(SchichtaCore.formatGermanDate(store.selectedDay))"), systemImage: "play.fill")
                                    }
                                    if !store.lastHookResult.isEmpty {
                                        Text(store.lastHookResult)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                } else {
                                    Button(store.t("main.noHookSetUpOpen")) {
                                        showTargetsSheet = false
                                        appDelegate()?.showSettings(tab: .integrations)
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
                    Button(store.t("main.done")) { showTargetsSheet = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 680, height: 540)
        }
        .alert(store.t("main.deleteEntry"), isPresented: $showDeleteAlert, presenting: entryToDelete) { entry in
            Button(store.t("main.cancel"), role: .cancel) { }
            Button(store.t("main.delete"), role: .destructive) {
                store.deleteEntry(id: entry.id)
                if editingEntryId == entry.id { resetForm() }
            }
        } message: { entry in
            Text(store.t("main.doYouReallyWantTo", "\(entry.description)"))
        }
    }

    /// Metrics, entry form, entries and notes for the selected day, with the inspector on the right.
    var dayView: some View {
        VStack(spacing: 0) {
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
    }

    // MARK: - Form Helper

    func addStepsToDuration(_ steps: Int) {
        let current = (try? SchichtaCore.parseMinutes(formDuration)) ?? 0
        formDuration = SchichtaCore.formatTime(store.snapDuration(current + steps * store.timeStepMinutes))
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
        formDuration = SchichtaCore.formatTime(store.timeStepMinutes)
        formDescription = ""
        formEstimated = false
    }

    func saveForm() {
        guard let minutes = try? SchichtaCore.parseMinutes(formDuration) else {
            store.showToast(store.t("main.invalidDurationPleaseEnterAs"))
            return
        }

        if let editId = editingEntryId {
            store.updateEntry(id: editId, ticket: formTicket, description: formDescription, minutes: minutes, estimated: formEstimated)
        } else {
            store.addEntry(ticket: formTicket, description: formDescription, minutes: minutes, estimated: formEstimated)
        }

        resetForm()
    }
}
