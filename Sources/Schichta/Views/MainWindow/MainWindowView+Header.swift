import AppKit
import SwiftUI

// MARK: - Main Window View (100% Native SwiftUI)

struct DatePickerPopoverContent: View {
    @ObservedObject var store: SchichtaStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 8) {
            DatePicker("", selection: Binding(
                get: { store.selectedDate },
                set: { newDate in
                    store.selectDate(newDate)
                    isPresented = false
                }
            ), displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .labelsHidden()
            .fixedSize()

            Divider()

            HStack {
                Button(store.t("main.today")) {
                    store.selectToday()
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(SchichtaTheme.forestGreen)
                .font(.system(size: 12, weight: .medium))

                Spacer()

                Button(store.t("main.done")) {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(10)
        .frame(width: 200)
    }
}

extension MainWindowView {
    // MARK: - Custom macOS Header Bar

    var customHeaderBar: some View {
        HStack(spacing: 14) {
            // Left: app logo + "Schichta" + weekday
            HStack(spacing: 9) {
                Image(nsImage: AppIconGenerator.small)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .cornerRadius(5)

                Text("Schichta")
                    .font(.system(size: 15, weight: .bold))

                if !isWeek {
                    Text(SchichtaCore.weekdayName(store.selectedDay, language: store.appLanguage))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1) // gives way first in a narrow window
                }
            }

            Spacer(minLength: 16)

            Picker("", selection: $store.mainViewMode) {
                Text(store.t("main.day")).tag(MainViewMode.day)
                Text(store.t("main.week")).tag(MainViewMode.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(store.t("main.dayViewOrWeekOverview"))

            // Center/right: date segment group
            datePickerCapsule

            // Far right: actions
            headerActionButtons
        }
        .padding(.leading, 82)
        .padding(.trailing, 20)
        .frame(height: 52)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.primary.opacity(0.08)),
            alignment: .bottom
        )
    }

    var datePickerCapsule: some View {
        HStack(spacing: 2) {
            Button(action: { isWeek ? store.moveWeek(-1) : store.moveDay(-1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isWeek ? store.t("main.previousWeek") : store.t("main.previousDay"))

            Button(action: { showDatePickerPopover.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(SchichtaTheme.forestGreen)
                    Text(dateCapsuleLabel)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .fixedSize()
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDatePickerPopover, arrowEdge: .bottom) {
                DatePickerPopoverContent(store: store, isPresented: $showDatePickerPopover)
            }
            .help(store.t("main.selectDateInCalendar"))

            Button(action: { isWeek ? store.moveWeek(1) : store.moveDay(1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isWeek ? store.t("main.nextWeek") : store.t("main.nextDay"))

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            Button(action: { store.selectToday() }) {
                Text(store.t("main.today"))
                    .font(.system(size: 11.5, weight: .medium))
                    .fixedSize()
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.t("main.jumpToToday"))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    var isWeek: Bool { store.mainViewMode == .week }

    /// Icon and title; only the icon when the header runs out of room (the tooltip keeps the meaning).
    func compactLabel(_ title: String, icon: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title).fixedSize()
            }
            Image(systemName: icon)
        }
        .font(.system(size: 12.5, weight: .semibold))
    }

    /// "26.10.2026", or in the week view "KW 44 · 26.10.–01.11.".
    var dateCapsuleLabel: String {
        guard isWeek else { return SchichtaCore.formatGermanDate(store.selectedDay) }
        let week = store.weekSummary(containing: store.selectedDay)
        let short = { (day: String) in String(SchichtaCore.formatGermanDate(day).prefix(6)) }
        return store.t("main.w", "\(week.weekNumber)", "\(short(week.start))", "\(short(week.end))")
    }

    var headerActionButtons: some View {
        HStack(spacing: 8) {
            // AI and analysis work on one day: hidden in the week view
            if !isWeek {
            Button(action: { showAISheet = true }) {
                compactLabel(store.t("main.ai"), icon: "wand.and.stars")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(store.t("main.summarizeTheDayFromNotes"))

            Button(action: { store.synthesizeDayAction() }) {
                compactLabel(store.t("main.analyzeDay"), icon: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(SchichtaTheme.forestGreen)
            .controlSize(.regular)
            .help(store.t("main.automaticallyAnalyzeLocalGitCommits"))
            }

            Button(action: { appDelegate()?.openSettingsWindow() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .help(store.t("main.settings"))

            Menu {
                Button(action: { appDelegate()?.showCheckInPanel() }) {
                    Label(store.t("main.openCheckInK"), systemImage: "clock")
                }

                Menu {
                    absenceMenuItems(for: store.selectedDay)
                } label: {
                    Label(store.t("main.markAs", "\(SchichtaCore.formatGermanDate(store.selectedDay))"), systemImage: "calendar.badge.minus")
                }

                Button(action: { appDelegate()?.openSettingsWindow() }) {
                    Label(store.t("main.settings"), systemImage: "gearshape")
                }

                #if DEBUG
                Divider()

                Button(action: { store.triggerMorningPromptManually() }) {
                    Label(store.t("main.testMorningPromptPreviousDay"), systemImage: "sunrise")
                }

                Button(action: { store.triggerEndOfDayPromptManually() }) {
                    Label(store.t("main.testEndOfDayPrompt"), systemImage: "sunset")
                }
                #endif

                Divider()

                Button(action: { store.exportMonthCSV(window: NSApp.keyWindow) }) {
                    Label(store.t("main.exportMonthAsCsv"), systemImage: "tablecells")
                }

                Button(action: { store.exportBackup(window: NSApp.keyWindow) }) {
                    Label(store.t("main.exportBackup"), systemImage: "square.and.arrow.up")
                }

                Button(action: { store.importBackup(window: NSApp.keyWindow) }) {
                    Label(store.t("main.importBackup"), systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28, height: 28)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .help(store.t("main.moreActions"))
        }
    }
}
