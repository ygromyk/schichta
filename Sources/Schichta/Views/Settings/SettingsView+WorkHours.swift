import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Tab 2: Work Hours & Prompts

    var workHoursAndPromptsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label(store.t("Reguläre Arbeitstage", "Regular Working Days"), systemImage: "calendar")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.t("Wähle deine regulären Arbeitstage. An freien Tagen ruhen automatische Prompts.", "Select your regular working days. Automatic prompts are paused on non-working days."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        let days: [(Int, String, String)] = [
                            (2, "Mo", "Mon"),
                            (3, "Di", "Tue"),
                            (4, "Mi", "Wed"),
                            (5, "Do", "Thu"),
                            (6, "Fr", "Fri"),
                            (7, "Sa", "Sat"),
                            (1, "So", "Sun")
                        ]
                        ForEach(days, id: \.0) { dayId, deLabel, enLabel in
                            let label = store.t(deLabel, enLabel)
                            let isSelected = store.workingDays.contains(dayId)
                            Button(action: {
                                if isSelected {
                                    if store.workingDays.count > 1 {
                                        store.workingDays.remove(dayId)
                                    }
                                } else {
                                    store.workingDays.insert(dayId)
                                }
                            }) {
                                Text(label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 44, height: 32)
                                    .background(isSelected ? SchichtaTheme.forestGreen : Color(nsColor: .controlBackgroundColor))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isSelected ? SchichtaTheme.forestGreen : Color(nsColor: .separatorColor), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(store.t("\(label) als Arbeitstag umschalten", "Toggle \(label) as working day"))
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(label: Label(store.t("Tagessoll & Arbeitszeitfenster", "Daily Target & Work Hours"), systemImage: "hourglass")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(store.t("Tägliche Soll-Arbeitszeit:", "Daily target work time:"))
                            .font(.system(size: 12, weight: .medium))
                        Spacer()

                        StepButton(increase: false, size: 16, help: store.t("−30 Minuten", "−30 minutes")) {
                            store.dailyTargetMinutes = max(60, store.dailyTargetMinutes - 30)
                        }

                        Text(String(format: "%@ h", SchichtaCore.formatTime(store.dailyTargetMinutes)))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .frame(width: 75, alignment: .center)

                        StepButton(increase: true, size: 16, help: store.t("+30 Minuten", "+30 minutes")) {
                            store.dailyTargetMinutes = min(840, store.dailyTargetMinutes + 30)
                        }

                        HStack(spacing: 3) {
                            ForEach([360, 420, 450, 480], id: \.self) { mins in
                                Button("\(mins / 60)\(mins % 60 != 0 ? ".5" : "")h") {
                                    store.dailyTargetMinutes = mins
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10, weight: store.dailyTargetMinutes == mins ? .bold : .regular))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(store.dailyTargetMinutes == mins ? SchichtaTheme.forestGreen.opacity(0.15) : Color.clear)
                                .cornerRadius(4)
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text(store.t("Arbeitszeit-Fenster:", "Work hours window:"))
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        HStack(spacing: 6) {
                            Picker("", selection: Binding(
                                get: { String(format: "%02d:%02d", store.workStartHour, store.workStartMinute) },
                                set: { val in
                                    let parts = val.split(separator: ":").compactMap { Int($0) }
                                    if parts.count == 2 {
                                        store.workStartHour = parts[0]
                                        store.workStartMinute = parts[1]
                                    }
                                }
                            )) {
                                ForEach(["07:00", "07:30", "08:00", "08:30", "09:00", "09:30", "10:00"], id: \.self) { t in
                                    Text(t).tag(t)
                                }
                            }
                            .frame(width: 80)

                            Text(store.t("bis", "to"))
                                .foregroundColor(.secondary)

                            Picker("", selection: Binding(
                                get: { String(format: "%02d:%02d", store.workEndHour, store.workEndMinute) },
                                set: { val in
                                    let parts = val.split(separator: ":").compactMap { Int($0) }
                                    if parts.count == 2 {
                                        store.workEndHour = parts[0]
                                        store.workEndMinute = parts[1]
                                    }
                                }
                            )) {
                                ForEach(["15:00", "15:30", "16:00", "16:30", "17:00", "17:30", "18:00", "18:30", "19:00", "20:00"], id: \.self) { t in
                                    Text(t).tag(t)
                                }
                            }
                            .frame(width: 80)
                        }
                    }

                    Toggle(store.t("Automatische Prompts nur an Arbeitstagen & innerhalb der Arbeitszeit", "Automatic prompts only on work days & during work hours"), isOn: $store.onlyPromptDuringWorkHours)
                        .font(.system(size: 12))

                    Divider()

                    OvertimeAccountSettings(store: store)
                }
                .padding(10)
            }

            GroupBox(label: Label(store.t("Check-in-Assistent & Prompts", "Check-in Assistant & Prompts"), systemImage: "bell.badge")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle(store.t("Regelmäßiger Check-in-Timer aktiv", "Regular check-in timer active"), isOn: $store.timerEnabled)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        HStack(spacing: 4) {
                            StepButton(increase: false, size: 14) {
                                store.reminderIntervalMinutes = max(5, store.reminderIntervalMinutes <= 15 ? store.reminderIntervalMinutes - 5 : store.reminderIntervalMinutes - 15)
                            }

                            let intervals = [5, 10, 15, 20, 30, 45, 60, 90]
                            Picker("", selection: $store.reminderIntervalMinutes) {
                                if !intervals.contains(store.reminderIntervalMinutes) {
                                    Text("\(store.reminderIntervalMinutes) min").tag(store.reminderIntervalMinutes)
                                }
                                ForEach(intervals, id: \.self) { mins in
                                    Text("\(mins) min").tag(mins)
                                }
                            }
                            .frame(width: 85)

                            StepButton(increase: true, size: 14) {
                                store.reminderIntervalMinutes = min(240, store.reminderIntervalMinutes + 15)
                            }
                        }
                    }

                    Divider()

                    Toggle(store.t("Morgen-Prompt: An ungebuchten Vortag erinnern", "Morning prompt: Remind if previous work day is unbooked"), isOn: $store.morningPromptEnabled)
                        .font(.system(size: 12))

                    Toggle(store.t("Feierabend-Prompt: Zum Arbeitsende an Tagesabschluss erinnern", "End-of-day prompt: Remind to close day at end of work hours"), isOn: $store.endOfDayPromptEnabled)
                        .font(.system(size: 12))

                    HStack {
                        Toggle(store.t("Mittags-Prompt: Vor der Pause nach dem Vormittag fragen", "Lunch prompt: Ask about the morning before the break"), isOn: $store.lunchPromptEnabled)
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { String(format: "%02d:%02d", store.lunchHour, store.lunchMinute) },
                            set: { val in
                                let parts = val.split(separator: ":").compactMap { Int($0) }
                                if parts.count == 2 {
                                    store.lunchHour = parts[0]
                                    store.lunchMinute = parts[1]
                                }
                            }
                        )) {
                            ForEach(["11:00", "11:30", "11:45", "12:00", "12:15", "12:30", "13:00", "13:30"], id: \.self) { t in
                                Text(t).tag(t)
                            }
                        }
                        .frame(width: 80)
                        .disabled(!store.lunchPromptEnabled)
                    }

                    HStack {
                        Toggle(store.t("Abwesenheit erkennen: nach Rückkehr fragen, was die Lücke war", "Detect time away: ask what the gap was when you're back"), isOn: $store.awayDetectionEnabled)
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $store.awayMinimumMinutes) {
                            ForEach([5, 10, 15, 20, 30], id: \.self) { mins in
                                Text(store.t("ab \(mins) min", "≥ \(mins) min")).tag(mins)
                            }
                        }
                        .frame(width: 115)
                        .disabled(!store.awayDetectionEnabled)
                    }
                    Text(store.t("Leerlauf, Ruhezustand und Bildschirmsperre zählen als weg. Während du weg bist, gibt es keine Check-ins; ein unbeantworteter Check-in meldet sich nach 3 Minuten per Mitteilung.", "Idle time, sleep and the lock screen count as away. No check-ins while you're away; an unanswered check-in sends a notification after 3 minutes."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Divider()

                    Toggle(store.t("Kurzen Sound bei Check-in & Prompts abspielen", "Play short sound on check-in & prompts"), isOn: $store.checkInSoundEnabled)
                        .font(.system(size: 12))

                    if store.checkInSoundEnabled {
                        HStack(spacing: 8) {
                            Text(store.t("Ton:", "Sound:"))
                                .font(.system(size: 12, weight: .medium))

                            Picker("", selection: $store.checkInSoundName) {
                                ForEach(SchichtaStore.availableSounds, id: \.self) { sName in
                                    Text(sName).tag(sName)
                                }
                            }
                            .frame(width: 120)

                            Button(action: {
                                appDelegate()?.playCheckInSound(customName: store.checkInSoundName)
                            }) {
                                HStack(spacing: 4) {
                                    Text("🔊")
                                    Text(store.t("Vorschau", "Preview"))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(store.t("Klangprobe abspielen", "Play sound preview"))
                        }
                        .padding(.leading, 18)
                    }
                }
                .padding(10)
            }
        }
    }
}

/// Start date and opening balance of the overtime account (shown in the week view).
struct OvertimeAccountSettings: View {
    @ObservedObject var store: SchichtaStore
    @State private var openingText = ""
    @State private var openingInvalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.t("Überstundenkonto ab:", "Overtime account from:"))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle(store.t("Festes Startdatum", "Fixed start date"), isOn: Binding(
                    get: { !store.overtimeStartDate.isEmpty },
                    set: { store.overtimeStartDate = $0 ? store.overtimeStart() : "" }
                ))
                .font(.system(size: 12))
                if !store.overtimeStartDate.isEmpty {
                    DatePicker("", selection: Binding(
                        get: { SchichtaCore.date(fromDay: store.overtimeStart()) },
                        set: { store.overtimeStartDate = SchichtaCore.day(from: $0) }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 120)
                } else {
                    Text(store.t("erster Eintrag (\(SchichtaCore.formatGermanDate(store.overtimeStart())))", "first entry (\(SchichtaCore.formatGermanDate(store.overtimeStart())))"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Text(store.t("Startsaldo:", "Opening balance:"))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                TextField("+0:00", text: $openingText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .onSubmit(applyOpening)
                    .help(store.t("z. B. +12:30 oder -4:00, mit Enter übernehmen", "e.g. +12:30 or -4:00, Enter to apply"))
                Text(store.t("Konto heute: \(SchichtaCore.formatSignedTime(store.overtimeBalance()))", "Account today: \(SchichtaCore.formatSignedTime(store.overtimeBalance()))"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 170, alignment: .trailing)
            }
            if openingInvalid {
                Text(store.t("Bitte als +12:30, -4:00 oder 1,5 eingeben.", "Please enter as +12:30, -4:00 or 1.5."))
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
            Text(store.t("Saldo = Startsaldo + Erfasst − Soll für jeden Tag seit dem Startdatum. Urlaub, Krank und Feiertage haben kein Soll.",
                         "Balance = opening balance + logged − target for every day since the start date. Vacation, sick and holidays have no target."))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .onAppear { openingText = SchichtaCore.formatSignedTime(store.overtimeOpeningMinutes) }
    }

    private func applyOpening() {
        guard let minutes = SchichtaCore.parseSignedHours(openingText) else {
            openingInvalid = true
            return
        }
        openingInvalid = false
        store.overtimeOpeningMinutes = minutes
        openingText = SchichtaCore.formatSignedTime(minutes)
    }
}
