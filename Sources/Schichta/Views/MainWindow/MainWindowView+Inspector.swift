import AppKit
import SwiftUI

extension MainWindowView {
    // MARK: - Right Column (Inspector: BCS Report)

    var inspectorColumn: some View {
        let entries = store.entriesForSelectedDay()
        let reportText = SchichtaCore.bcsReport(day: store.selectedDay, entries: entries)
        let totalMinutes = entries.reduce(0) { $0 + $1.minutes }
        let estimatesCount = entries.filter { $0.estimated }.count

        // Scrollable, so nothing is squeezed or cut off in a short window.
        return ScrollView { VStack(alignment: .leading, spacing: 14) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t("main.dayEndSummary"))
                    .font(.system(size: 16, weight: .bold))
                Text(store.t("main.bookingDraftFor", "\(store.gitAuthorFilter)"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Review Banner
            if totalMinutes == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text(store.t("main.noEntriesYetLogYour"))
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else if estimatesCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(store.t("main.verifyEstimatedDurationSBefore", "\(estimatesCount)"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(SchichtaTheme.forestGreen)
                    Text(store.t("main.durationsVerifiedReadyToTransfer"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(SchichtaTheme.forestGreen)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SchichtaTheme.forestGreen.opacity(0.12))
                .cornerRadius(8)
            }

            // Monospace Report Preview
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.t("main.draft"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(SchichtaCore.formatGermanDate(store.selectedDay))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                ScrollView {
                    Text(entries.isEmpty ? store.t("main.yourDailyDraftWillAppear") : reportText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 140, maxHeight: 280)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }

            // Action Buttons
            VStack(spacing: 8) {
                Button(action: { store.copyBCSReport() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text(store.t("main.copyDailyDraft"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .prominentWhenEnabled(!entries.isEmpty)

                Button(action: { showTargetsSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane")
                        Text(store.t("main.bookTo"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(entries.isEmpty)

                let isBooked = store.journalForSelectedDay().booked
                if !isBooked {
                    Button(action: { store.copyBCSReportAndMarkBooked() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal")
                            Text(store.t("main.copyMarkAsBooked"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(entries.isEmpty)
                }

                Button(action: { store.saveBCSReportToFile(window: NSApp.keyWindow) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text(store.t("main.saveAsTxt"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(entries.isEmpty)

                // Prominent status button / toggle
                bookingStatusCard
            }

            // Info Hint
            VStack(alignment: .leading, spacing: 4) {
                Text(store.t("main.note"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(store.t("main.copyTheDraftAndEnter"))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
        .padding(18) }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var bookingStatusCard: some View {
        let isBooked = store.journalForSelectedDay().booked
        return Group {
            if isBooked {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(SchichtaTheme.forestGreen)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.t("main.dayIsBookedCompleted"))
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(SchichtaTheme.forestGreen)
                        Text(store.t("main.recordedInBookingSystem"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(store.t("main.reopen")) {
                        store.toggleDayBooked()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(SchichtaTheme.forestGreen.opacity(0.12))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(SchichtaTheme.forestGreen.opacity(0.35), lineWidth: 1))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "circle.dashed")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.t("main.dayNotYetBooked"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                        Text(store.t("main.notCompletedYet"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 4)
                    Button(store.t("main.markAsBooked")) {
                        store.toggleDayBooked()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SchichtaTheme.forestGreen)
                    .controlSize(.small)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.35), lineWidth: 1))
            }
        }
    }
}
