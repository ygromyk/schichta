import AppKit
import SwiftUI

extension MainWindowView {
    // MARK: - Prompt Banners

    func morningPromptBanner(unbookedDay: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(nsImage: AppIconGenerator.small)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t("Guten Morgen! Der Vortag (\(SchichtaCore.formatGermanDate(unbookedDay))) ist noch nicht gebucht.", "Good morning! The previous work day (\(SchichtaCore.formatGermanDate(unbookedDay))) is not booked yet."))
                        .font(.system(size: 13, weight: .bold))
                    Text(store.t("Deine Buchungen vom \(SchichtaCore.formatGermanDate(unbookedDay)) sind noch nicht übertragen.", "Your bookings from \(SchichtaCore.formatGermanDate(unbookedDay)) have not been transferred yet."))
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
                .help(store.t("Hinweis schließen", "Close banner"))
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
                        Text(store.t("Zum Vortag wechseln & prüfen", "Switch to previous day & review"))
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
                        Text(store.t("Entwurf kopieren & als gebucht markieren ✓", "Copy draft & mark as booked ✓"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SchichtaTheme.forestGreen)
                .controlSize(.small)

                Button(store.t("Ignorieren / Bereits gebucht", "Ignore / Already booked")) {
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
                    Text(store.t("Tagesabschluss: Möchtest du deine heutigen Buchungen (\(SchichtaCore.formatGermanDate(day))) jetzt abschließen?", "Day completion: Would you like to close today's bookings (\(SchichtaCore.formatGermanDate(day))) now?"))
                        .font(.system(size: 13, weight: .bold))
                    Text(store.t("Tätigkeiten für \(SchichtaCore.formatGermanDate(day)) auswerten und buchen.", "Analyze activities for \(SchichtaCore.formatGermanDate(day)) and book them."))
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
                .help(store.t("Hinweis schließen", "Close banner"))
            }

            HStack(spacing: 8) {
                Button(action: {
                    store.selectDay(day)
                    store.synthesizeDayAction()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text(store.t("Tag automatisch auswerten", "Automatically analyze day"))
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
                        Text(store.t("Entwurf kopieren & Tag abschließen ✓", "Copy draft & complete day ✓"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SchichtaTheme.forestGreen)
                .controlSize(.small)

                Button(store.t("Später erinnern", "Remind me later")) {
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
