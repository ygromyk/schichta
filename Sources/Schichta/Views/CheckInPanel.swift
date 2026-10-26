import AppKit
import SwiftUI

// MARK: - Visual Effect & Check-In Panel

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

class CheckInPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

// MARK: - Statusbar Check-In Popover View (SwiftUI)

struct CheckInPopoverView: View {
    @ObservedObject var store: SchichtaStore
    var onClose: () -> Void

    @State private var ticketText: String = ""
    @State private var noteText: String = ""
    @State private var durationText: String = "0:15"
    @State private var mode: CheckInMode = .both
    @State private var isSaved: Bool = false
    @FocusState private var isNoteFocused: Bool

    private var durationMinutes: Int {
        (try? SchichtaCore.parseMinutes(durationText)) ?? store.reminderIntervalMinutes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(nsImage: AppIconGenerator.small)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.t("Was machst du gerade?", "What are you working on?"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(AppDelegate.checkInWindowString(intervalMinutes: durationMinutes, language: store.appLanguage))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $store.timerEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(store.t("\(store.reminderIntervalMinutes)-Minuten Intervall-Prompt aktivieren oder pausieren", "Enable or pause \(store.reminderIntervalMinutes)-minute interval prompt"))

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.7))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help(store.t("Schließen (Esc)", "Close (Esc)"))
            }

            // Quick Recent Tickets Chips
            let recents = store.recentTickets()
            if !recents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recents, id: \.self) { t in
                            Button(action: {
                                ticketText = t
                                isNoteFocused = true
                            }) {
                                Text(t)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(ticketText == t ? SchichtaTheme.forestGreen : Color(nsColor: .controlBackgroundColor))
                                    .foregroundColor(ticketText == t ? .white : .primary)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Input Card
            VStack(spacing: 0) {
                TextField(store.t("Ticket optional (z. B. PROJ-2800)", "Ticket optional (e.g. PROJ-2800)"), text: $ticketText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)

                Divider()

                TextField(store.t("Kurze Notiz: Woran arbeitest du gerade?", "Short note: What are you working on?"), text: $noteText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .focused($isNoteFocused)
                    .onSubmit {
                        submitCheckIn()
                    }

                Divider()

                // Dauer & Quick-Chips
                HStack(spacing: 6) {
                    Text(store.t("Dauer:", "Duration:"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    StepButton(increase: false, size: 16, help: store.t("−15 Minuten (mind. 5 Min.)", "−15 minutes (min. 5 min.)")) { adjustDuration(delta: -15) }

                    TextField("0:15", text: $durationText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 58)

                    StepButton(increase: true, size: 16, help: store.t("+15 Minuten", "+15 minutes")) { adjustDuration(delta: 15) }

                    Spacer(minLength: 4)

                    quickChipButton("15m") { setDuration(15) }
                    quickChipButton("30m") { setDuration(30) }
                    quickChipButton("45m") { setDuration(45) }
                    quickChipButton("1h") { setDuration(60) }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            // Mode Picker & Save Button
            HStack(spacing: 10) {
                Picker("", selection: $mode) {
                    ForEach(CheckInMode.allCases) { m in
                        Text(m.title(for: store.appLanguage)).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button(action: submitCheckIn) {
                    Text(isSaved ? store.t("✓ Gespeichert", "✓ Saved") : store.t("Speichern ↵", "Save ↵"))
                        .font(.system(size: 12, weight: .semibold))
                        .frame(minWidth: 100)
                }
                .prominentWhenEnabled(!(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaved))
            }

            Divider()

            // Footer
            HStack {
                Button(store.t("Hauptfenster", "Main window")) {
                    appDelegate()?.showMainWindow(nil)
                    onClose()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

                Spacer()

                Button(store.t("Später (+\(store.reminderIntervalMinutes)m)", "Later (+\(store.reminderIntervalMinutes)m)")) {
                    appDelegate()?.snoozeCheckIn()
                    onClose()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    appDelegate()?.openSettingsWindow()
                    onClose()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(store.t("Einstellungen… (⌘,)", "Settings… (⌘,)"))

                Spacer()

                Button(store.t("Beenden", "Quit")) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 380)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .onAppear {
            mode = store.defaultCheckInMode
            durationText = SchichtaCore.formatTime(store.reminderIntervalMinutes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNoteFocused = true
            }
        }
    }

    private func quickChipButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color(nsColor: .controlColor))
                .foregroundColor(.primary)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func adjustDuration(delta: Int) {
        let cur = (try? SchichtaCore.parseMinutes(durationText)) ?? store.reminderIntervalMinutes
        let next = SchichtaCore.clampDuration(cur + delta)
        durationText = SchichtaCore.formatTime(next)
    }

    private func setDuration(_ minutes: Int) {
        durationText = SchichtaCore.formatTime(minutes)
    }

    private func submitCheckIn() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSSound.beep()
            return
        }

        let timeStr = AppDelegate.checkInCurrentTimeString()
        let minutes = (try? SchichtaCore.parseMinutes(durationText)) ?? store.reminderIntervalMinutes
        store.handleCheckIn(text: trimmed, ticket: ticketText, mode: mode, timeStr: timeStr, minutes: minutes)

        isSaved = true
        appDelegate()?.isCheckInDue = false
        appDelegate()?.updateStatusItem(isDue: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            onClose()
        }
    }
}
