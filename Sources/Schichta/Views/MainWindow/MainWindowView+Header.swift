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
                Button(store.t("Heute", "Today")) {
                    store.selectToday()
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(SchichtaTheme.forestGreen)
                .font(.system(size: 12, weight: .medium))

                Spacer()

                Button(store.t("Fertig", "Done")) {
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

                Text(SchichtaCore.weekdayName(store.selectedDay, language: store.appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

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
            Button(action: { store.moveDay(-1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.t("Vorheriger Tag", "Previous day"))

            Button(action: { showDatePickerPopover.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(SchichtaTheme.forestGreen)
                    Text(SchichtaCore.formatGermanDate(store.selectedDay))
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
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
            .help(store.t("Datum im Kalender wählen", "Select date in calendar"))

            Button(action: { store.moveDay(1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.t("Nächster Tag", "Next day"))

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            Button(action: { store.selectToday() }) {
                Text(store.t("Heute", "Today"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.t("Zu heute springen", "Jump to today"))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    var headerActionButtons: some View {
        HStack(spacing: 8) {
            Button(action: { showAISheet = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "wand.and.stars")
                    Text(store.t("KI", "AI"))
                }
                .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(store.t("Tag mit Notizen, Git und Claude-/Codex-Chats per KI zusammenfassen", "Summarize the day from notes, Git and Claude/Codex chats via AI"))

            Button(action: { store.synthesizeDayAction() }) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                    Text(store.t("Tag auswerten", "Analyze day"))
                }
                .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(SchichtaTheme.forestGreen)
            .controlSize(.regular)
            .help(store.t("Lokale Git-Commits, Reflogs und Notizen automatisch auswerten", "Automatically analyze local Git commits, reflogs and notes"))

            Button(action: { appDelegate()?.openSettingsWindow() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .help(store.t("Einstellungen… (⌘,)", "Settings… (⌘,)"))

            Menu {
                Button(action: { appDelegate()?.triggerCheckInPrompt() }) {
                    Label(store.t("Check-in öffnen (⌘K)", "Open check-in (⌘K)"), systemImage: "clock")
                }

                Button(action: { appDelegate()?.openSettingsWindow() }) {
                    Label(store.t("Einstellungen… (⌘,)", "Settings… (⌘,)"), systemImage: "gearshape")
                }

                Divider()

                Button(action: { store.triggerMorningPromptManually() }) {
                    Label(store.t("Morgen-Prompt (Vortag) testen", "Test morning prompt (previous day)"), systemImage: "sunrise")
                }

                Button(action: { store.triggerEndOfDayPromptManually() }) {
                    Label(store.t("Feierabend-Prompt testen", "Test end-of-day prompt"), systemImage: "sunset")
                }

                Divider()

                Button(action: { store.exportBackup(window: NSApp.keyWindow) }) {
                    Label(store.t("Sicherung exportieren...", "Export backup..."), systemImage: "square.and.arrow.up")
                }

                Button(action: { store.importBackup(window: NSApp.keyWindow) }) {
                    Label(store.t("Sicherung importieren...", "Import backup..."), systemImage: "square.and.arrow.down")
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
            .help(store.t("Weitere Aktionen", "More actions"))
        }
    }
}
