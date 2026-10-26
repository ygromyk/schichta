import AppKit
import SwiftUI

extension MainWindowView {
    // MARK: - Top Status Metrics Bar (4 Tiles)

    var topMetricsBar: some View {
        let entries = store.entriesForSelectedDay()
        let totalMinutes = entries.reduce(0) { $0 + $1.minutes }
        let estimatesCount = entries.filter { $0.estimated }.count
        let openTicketsCount = entries.filter { $0.ticket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.ticket == "PROJ-0" }.count
        let target = store.dailyTargetMinutes > 0 ? store.dailyTargetMinutes : 480
        let progress = min(1.0, Double(totalMinutes) / Double(target))

        return HStack(spacing: 12) {
            // Tile 1: logged time
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(SchichtaTheme.forestGreen)
                        .font(.system(size: 11))
                    Text(store.t("Erfasste Zeit", "Logged time"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(SchichtaCore.formatTime(totalMinutes))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("h")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(totalMinutes >= target ? store.t("\(SchichtaCore.formatTime(target)) h voll", "\(SchichtaCore.formatTime(target)) h reached") : store.t("von \(SchichtaCore.formatTime(target)) h", "of \(SchichtaCore.formatTime(target)) h"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(SchichtaTheme.forestGreen)
            }
            .tileStyle()

            // Tile 2: activities
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 11))
                    Text(store.t("Tätigkeiten", "Activities"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Text("\(entries.count)")
                    .font(.system(size: 20, weight: .bold))
                Text(entries.count == 1 ? store.t("1 Eintrag heute", "1 entry today") : store.t("\(entries.count) Einträge heute", "\(entries.count) entries today"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .tileStyle()

            // Tile 3: review status
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if totalMinutes == 0 {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    } else if totalMinutes > 1440 {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                    } else if store.journalForSelectedDay().booked {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(SchichtaTheme.forestGreen)
                            .font(.system(size: 11))
                    } else if estimatesCount > 0 || openTicketsCount > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(SchichtaTheme.forestGreen)
                            .font(.system(size: 11))
                    }
                    Text(store.t("Prüfstatus", "Review status"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                if totalMinutes == 0 {
                    Text(store.t("Keine Einträge", "No entries"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(store.t("Beginne mit der 1. Tätigkeit", "Start with your 1st entry"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if totalMinutes > 1440 {
                    Text(store.t("Über 24 Stunden!", "Over 24 hours!"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red)
                    Text(store.t("Bitte Zeiten korrigieren", "Please correct durations"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if store.journalForSelectedDay().booked {
                    Text(store.t("Gebucht", "Booked"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SchichtaTheme.forestGreen)
                    Text(store.t("Tag ist abgeschlossen", "Day is completed"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if estimatesCount > 0 || openTicketsCount > 0 {
                    Text(estimatesCount == 1 ? store.t("1 Schätzung", "1 estimate") : store.t("\(estimatesCount) Schätzungen", "\(estimatesCount) estimates"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                    Text(openTicketsCount > 0 ? (openTicketsCount == 1 ? store.t("1 ohne Ticket", "1 without ticket") : store.t("\(openTicketsCount) ohne Ticket", "\(openTicketsCount) without ticket")) : store.t("Vor Buchung prüfen", "Verify before booking"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(store.t("Bereit zur Buchung", "Ready to book"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SchichtaTheme.forestGreen)
                    Text(store.t("Alle Angaben geprüft", "All details verified"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .tileStyle()

            // Tile 4: check-in assistant & end-of-day prompt
            VStack(alignment: .leading, spacing: 4) {
                // Row 1: header
                HStack(alignment: .center, spacing: 5) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 11))
                    Text(store.t("Check-in-Assistent", "Check-in Assistant"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Circle()
                        .fill(store.timerEnabled && store.isCurrentlyWithinWorkingHours() ? SchichtaTheme.forestGreen : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Toggle("", isOn: $store.timerEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }

                // Row 2: main value
                HStack(alignment: .center, spacing: 4) {
                    let assistantStatusText: String = {
                        if !store.timerEnabled {
                            return store.t("Pausiert", "Paused")
                        }
                        let today = SchichtaCore.day()
                        if !store.isWorkingDay(today) {
                            return store.t("Wochenende", "Weekend")
                        }
                        if !store.isCurrentlyWithinWorkingHours() {
                            return store.t("Ruht", "Resting")
                        }
                        return store.t("Aktiv", "Active")
                    }()

                    Text(assistantStatusText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(store.timerEnabled && store.isCurrentlyWithinWorkingHours() ? .primary : .secondary)

                    Spacer()

                    StepButton(increase: false, size: 13, help: store.t("Intervall um 5/15 Min. verringern", "Decrease interval by 5/15 min")) {
                        store.reminderIntervalMinutes = max(5, store.reminderIntervalMinutes <= 15 ? store.reminderIntervalMinutes - 5 : store.reminderIntervalMinutes - 15)
                    }

                    Text("\(store.reminderIntervalMinutes) Min.")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))

                    StepButton(increase: true, size: 13, help: store.t("Intervall um 15 Min. erhöhen", "Increase interval by 15 min")) {
                        store.reminderIntervalMinutes = min(240, store.reminderIntervalMinutes + 15)
                    }
                }

                // Row 3: subtext
                HStack {
                    Text(store.t("Feierabend: \(store.endOfDayPromptTimeString) Uhr", "End of day: \(store.endOfDayPromptTimeString)"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button(action: {
                        store.openSettings(tab: 1)
                    }) {
                        Text(store.t("Ändern…", "Change…"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(SchichtaTheme.forestGreen)
                    }
                    .buttonStyle(.plain)
                    .help(store.t("Arbeitszeit & Feierabend in den Einstellungen anpassen", "Adjust work hours & end of day in settings"))
                }
            }
            .tileStyle()
        }
    }
}
