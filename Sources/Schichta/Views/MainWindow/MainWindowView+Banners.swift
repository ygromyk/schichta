import AppKit
import SwiftUI

extension MainWindowView {
    // MARK: - Data File Banner

    func storeProblemBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Button(store.t("main.showDataFolderInFinder")) {
                    store.revealDataFolder()
                }
                .controlSize(.small)
            }
            Spacer()
            Button(action: { withAnimation { store.storeProblem = nil } }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help(store.t("main.closeBanner"))
        }
        .bannerStyle(.red)
    }

    // MARK: - Day off

    func absenceBanner(_ absence: Absence, day: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: absence.icon)
                .foregroundColor(.purple)
                .font(.system(size: 16))
            Text(store.t("main.markedAs.\(absence.rawValue)", SchichtaCore.formatGermanDate(day)))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button(store.t("main.undo")) { store.setAbsence(nil, on: day) }
                .controlSize(.small)
        }
        .bannerStyle(.purple)
    }

    // MARK: - Prompt Banners

    func morningPromptBanner(unbookedDay: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(nsImage: AppIconGenerator.small)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t("main.goodMorningThePreviousWork", "\(SchichtaCore.formatGermanDate(unbookedDay))"))
                        .font(.system(size: 13, weight: .bold))
                    Text(store.t("main.yourBookingsFromHaveNot", "\(SchichtaCore.formatGermanDate(unbookedDay))"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { withAnimation { store.activePrompt = .none } }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help(store.t("main.closeBanner"))
            }

            HStack(spacing: 8) {
                Button(action: {
                    withAnimation {
                        store.selectDay(unbookedDay)
                        store.synthesizeDayAction()
                        store.activePrompt = .none
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text(store.t("main.switchToPreviousDayReview"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)

                Button(action: {
                    withAnimation {
                        store.copyBCSReportAndMarkBooked(day: unbookedDay)
                        store.activePrompt = .none
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text(store.t("main.copyDraftMarkAsBooked"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SchichtaTheme.forestGreen)
                .controlSize(.small)

                Button(store.t("main.ignoreAlreadyBooked")) {
                    withAnimation {
                        store.markDayBooked(unbookedDay, booked: true)
                        store.activePrompt = .none
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .bannerStyle(.orange)
    }

    func endOfDayPromptBanner(day: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(nsImage: AppIconGenerator.small)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t("main.dayCompletionWouldYouLike", "\(SchichtaCore.formatGermanDate(day))"))
                        .font(.system(size: 13, weight: .bold))
                    Text(store.t("main.analyzeActivitiesForAndBook", "\(SchichtaCore.formatGermanDate(day))"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { withAnimation { store.activePrompt = .none } }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help(store.t("main.closeBanner"))
            }

            HStack(spacing: 8) {
                Button(action: {
                    store.selectDay(day)
                    store.synthesizeDayAction()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text(store.t("main.automaticallyAnalyzeDay"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)

                Button(action: {
                    withAnimation {
                        store.copyBCSReportAndMarkBooked(day: day)
                        store.activePrompt = .none
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text(store.t("main.copyDraftCompleteDay"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SchichtaTheme.forestGreen)
                .controlSize(.small)

                Button(store.t("main.remindMeLater")) {
                    withAnimation {
                        store.activePrompt = .none
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .bannerStyle(.purple)
    }
}
