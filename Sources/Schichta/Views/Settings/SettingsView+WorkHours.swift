import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Tab 2: Arbeitszeit & Prompts

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
