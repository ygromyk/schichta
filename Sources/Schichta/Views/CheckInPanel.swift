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
        if let delegate = appDelegate() { delegate.closeCheckInPanel() } else { orderOut(sender) }
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
                    Text(headline)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

            // Back after time away: the gap can be a break
            if case .back(let period) = store.checkInRequest.reason {
                Button(action: {
                    store.logBreak(period)
                    appDelegate()?.checkInAnswered()
                    onClose()
                }) {
                    Label(store.t("Pause – nicht buchen", "Break – don't log"), systemImage: "cup.and.saucer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            // One click to continue the previous activity
            if let last = store.lastCheckIn() {
                Button(action: { repeatLast() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text(store.t("Wie zuvor:", "Same as before:"))
                            .foregroundColor(.secondary)
                        Text((last.ticket.isEmpty ? "" : "[\(last.ticket)] ") + last.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(store.t("Letzten Check-in mit der eingestellten Dauer wiederholen", "Log the last check-in again with the duration below"))
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

                TextField(notePlaceholder, text: $noteText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .focused($isNoteFocused)
                    .onSubmit {
                        submitCheckIn()
                    }

                Divider()

                // Duration & quick chips
                HStack(spacing: 6) {
                    Text(store.t("Dauer:", "Duration:"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    StepButton(increase: false, size: 16, help: store.t("−\(store.timeStepMinutes) Minuten", "−\(store.timeStepMinutes) minutes")) { adjustDuration(steps: -1) }

                    DurationInput(text: $durationText, step: store.timeStepMinutes)

                    StepButton(increase: true, size: 16, help: store.t("+\(store.timeStepMinutes) Minuten", "+\(store.timeStepMinutes) minutes")) { adjustDuration(steps: 1) }

                    Spacer(minLength: 4)

                    ForEach(store.durationPresets.prefix(4), id: \.self) { minutes in
                        quickChipButton(SchichtaCore.durationLabel(minutes)) { setDuration(minutes) }
                    }
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
        // The panel's view lives as long as the app: reset it for every new opening.
        .onChange(of: store.checkInRequest.id, initial: true) {
            noteText = ""
            ticketText = ""
            isSaved = false
            mode = store.defaultCheckInMode
            durationText = SchichtaCore.formatTime(store.prefilledMinutes(for: store.checkInRequest.reason))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNoteFocused = true
            }
        }
    }

    private var headline: String {
        switch store.checkInRequest.reason {
        case .manual, .timer: return store.t("Was machst du gerade?", "What are you working on?")
        case .beforeLunch: return store.t("Gleich Mittagspause? 🍽", "Off to lunch? 🍽")
        case .back: return store.t("Willkommen zurück", "Welcome back")
        }
    }

    private var subtitle: String {
        switch store.checkInRequest.reason {
        case .manual, .timer:
            return AppDelegate.checkInWindowString(intervalMinutes: durationMinutes, language: store.appLanguage)
        case .beforeLunch:
            return store.t("Was hast du heute Vormittag gemacht?", "What did you do this morning?")
        case .back(let period):
            let range = "\(AppTime.clock.string(from: period.from))–\(AppTime.clock.string(from: period.to))"
            return store.t("Weg von \(range) (\(SchichtaCore.formatTime(period.minutes))). Was war das?",
                           "Away \(range) (\(SchichtaCore.formatTime(period.minutes))). What was that?")
        }
    }

    private var notePlaceholder: String {
        switch store.checkInRequest.reason {
        case .manual, .timer: return store.t("Kurze Notiz: Woran arbeitest du gerade?", "Short note: What are you working on?")
        case .beforeLunch: return store.t("z. B. Review PROJ-2800, Daily, Bugfix Login", "e.g. review PROJ-2800, daily, login bugfix")
        case .back: return store.t("z. B. Meeting mit Team, Kundencall", "e.g. team meeting, customer call")
        }
    }

    private func repeatLast() {
        guard store.repeatLastCheckIn(minutes: durationMinutes, mode: mode) else { return }
        isSaved = true
        appDelegate()?.checkInAnswered()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            onClose()
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

    private func adjustDuration(steps: Int) {
        let cur = (try? SchichtaCore.parseMinutes(durationText)) ?? store.reminderIntervalMinutes
        let next = store.snapDuration(cur + steps * store.timeStepMinutes)
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
        appDelegate()?.checkInAnswered()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            onClose()
        }
    }
}
