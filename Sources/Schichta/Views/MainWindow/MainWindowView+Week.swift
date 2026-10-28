import AppKit
import SwiftUI

extension MainWindowView {
    // MARK: - Week Overview

    var weekOverview: some View {
        let week = store.weekSummary(containing: store.selectedDay)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !week.unbookedDays.isEmpty {
                    unbookedDaysBanner(week.unbookedDays)
                }

                weekTiles(week)

                HStack(alignment: .top, spacing: 16) {
                    sectionCard(
                        title: store.t("main.days"),
                        icon: "calendar",
                        trailing: {
                            Button(action: { showWeekBooking = true }) {
                                Label(store.t("main.bookWeek"), systemImage: "paperplane")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SchichtaTheme.forestGreen)
                            .controlSize(.small)
                            .disabled(week.unbookedDays.isEmpty && !week.days.contains { $0.isToday && !$0.booked && $0.minutes > 0 })
                            .help(store.t("main.sendAllOpenDaysOf"))

                            Button(action: { store.exportMonthCSV(window: NSApp.keyWindow) }) {
                                Label(store.t("main.monthAsCsv"), systemImage: "tablecells")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(store.t("main.exportAllEntriesOfThe"))
                        }
                    ) {
                        VStack(spacing: 6) {
                            ForEach(week.days, id: \.day) { day in
                                weekDayRow(day)
                            }
                            Text(store.t("main.clickOpensTheDayRight"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    sectionCard(
                        title: store.t("main.byTicket"),
                        icon: "number",
                        trailing: {
                            Button(action: {
                                store.copyToPasteboard(store.weekReport(week))
                                store.showToast(store.t("main.weekSummaryCopied"))
                            }) {
                                Label(store.t("main.copyWeek"), systemImage: "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(week.total == 0)
                        }
                    ) {
                        ticketTotalsList(week)
                    }
                    .frame(width: 360)
                }
            }
            .padding(20)
        }
    }

    private func unbookedDaysBanner(_ days: [String]) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16))
            Text(days.count == 1
                 ? store.t("main.1DayIsNotBooked")
                 : store.t("main.daysAreNotBookedYet", "\(days.count)"))
                .font(.system(size: 12, weight: .semibold))
            ForEach(days, id: \.self) { day in
                Button(shortDayLabel(day)) { store.openDay(day) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.35), lineWidth: 1))
    }

    private func weekTiles(_ week: WeekSummary) -> some View {
        let progress = week.target > 0 ? min(1.0, Double(week.total) / Double(week.target)) : 0
        let balance = week.balanceSoFar
        return HStack(spacing: 12) {
            weekTile(icon: "clock.fill", color: SchichtaTheme.forestGreen, title: store.t("main.weekTotal")) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(SchichtaCore.formatTime(week.total))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("h").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                    Spacer()
                    Text(store.t("main.ofH", "\(SchichtaCore.formatTime(week.target))"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(SchichtaTheme.forestGreen)
            }

            weekTile(icon: "plusminus", color: balance >= 0 ? SchichtaTheme.forestGreen : .orange, title: store.t("main.weekBalance")) {
                Text(SchichtaCore.formatSignedTime(balance))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(balance >= 0 ? SchichtaTheme.forestGreen : .orange)
                let account = store.overtimeBalance()
                let since = String(SchichtaCore.formatGermanDate(store.overtimeStart()).prefix(6))
                Text(store.t("main.accountSince", "\(SchichtaCore.formatSignedTime(account))", "\(since)"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(account >= 0 ? .secondary : .orange)
                    .lineLimit(1)
                    .help(store.t("main.overtimeAccountLoggedMinusTarget"))
            }

            weekTile(icon: "checkmark.seal.fill", color: .blue, title: store.t("main.bookedDays")) {
                Text("\(week.bookedWorkingDays) / \(week.workingDays)")
                    .font(.system(size: 20, weight: .bold))
                Text(store.t("main.workingDaysThisWeek"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            weekTile(icon: "questionmark.circle.fill", color: week.estimatedCount > 0 ? .orange : .secondary, title: store.t("main.estimates2")) {
                Text("\(week.estimatedCount)")
                    .font(.system(size: 20, weight: .bold))
                Text(week.estimatedCount == 0
                     ? store.t("main.allConfirmed")
                     : store.t("main.reviewBeforeBooking"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func weekTile<Content: View>(icon: String, color: Color, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            content()
        }
        .tileStyle()
    }

    private func weekDayRow(_ day: DaySummary) -> some View {
        let progress = day.target > 0 ? min(1.0, Double(day.minutes) / Double(day.target)) : (day.minutes > 0 ? 1.0 : 0)
        return Button(action: { store.openDay(day.day) }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(SchichtaCore.weekdayName(day.day, language: store.appLanguage))
                        .font(.system(size: 12, weight: day.isToday ? .bold : .semibold))
                    Text(SchichtaCore.formatGermanDate(day.day))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(width: 92, alignment: .leading)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(day.minutes >= day.target && day.target > 0 ? SchichtaTheme.forestGreen : .blue)
                    .opacity(day.isWorkingDay || day.minutes > 0 ? 1 : 0.35)

                Text(day.target > 0
                     ? "\(SchichtaCore.formatTime(day.minutes)) / \(SchichtaCore.formatTime(day.target))"
                     : SchichtaCore.formatTime(day.minutes))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(day.minutes > 0 ? .primary : .secondary)
                    .frame(width: 100, alignment: .trailing)

                if day.estimatedCount > 0 {
                    Text(store.t("main.estimated2", "\(day.estimatedCount)"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }

                dayStatusChip(day)
                    .frame(width: 78, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(day.isToday ? SchichtaTheme.forestGreen.opacity(0.08) : Color.clear)
            .cornerRadius(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(store.t("main.openDay", SchichtaCore.formatFullDate(day.day, language: store.appLanguage)))
        .contextMenu { absenceMenuItems(for: day.day) }
    }

    /// "Vacation / Sick / Holiday / Working day" for a day; used in the week rows and the header menu.
    @ViewBuilder
    func absenceMenuItems(for day: String) -> some View {
        let current = store.absence(on: day)
        ForEach(Absence.allCases, id: \.self) { kind in
            Button(action: { store.setAbsence(kind, on: day) }) {
                Label(kind.title(for: store.appLanguage) + (current == kind ? " ✓" : ""), systemImage: kind.icon)
            }
        }
        if current != nil {
            Divider()
            Button(action: { store.setAbsence(nil, on: day) }) {
                Label(store.t("main.normalWorkingDay"), systemImage: "briefcase")
            }
        }
    }

    private func dayStatusChip(_ day: DaySummary) -> some View {
        let (label, color): (String, Color) = {
            if let absence = day.absence { return (absence.title(for: store.appLanguage), .purple) }
            if day.booked { return (store.t("main.booked2"), SchichtaTheme.forestGreen) }
            if day.isToday { return (store.t("main.today"), .blue) }
            if day.isUnbooked { return (store.t("main.open"), .orange) }
            if day.isFuture { return ("–", .secondary) }
            return (store.t("main.off"), .secondary)
        }()
        return Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.12))
            .cornerRadius(5)
    }

    @ViewBuilder
    private func ticketTotalsList(_ week: WeekSummary) -> some View {
        if week.ticketTotals.isEmpty {
            Text(store.t("main.noEntriesThisWeekYet"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 18)
        } else {
            let maxMinutes = week.ticketTotals.map(\.minutes).max() ?? 1
            VStack(alignment: .leading, spacing: 8) {
                ForEach(week.ticketTotals, id: \.self) { total in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(total.ticket.isEmpty ? store.t("main.noTicket") : total.ticket)
                                .font(.system(size: 12, weight: .semibold, design: total.ticket.isEmpty ? .default : .monospaced))
                                .foregroundColor(total.ticket.isEmpty ? .secondary : .primary)
                            if !total.project.isEmpty {
                                Text(total.project)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(SchichtaCore.formatTime(total.minutes))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        ProgressView(value: Double(total.minutes) / Double(maxMinutes))
                            .progressViewStyle(.linear)
                            .tint(SchichtaTheme.forestGreen.opacity(0.7))
                    }
                }
            }
        }
    }

    private func shortDayLabel(_ day: String) -> String {
        "\(SchichtaCore.weekdayName(day, language: store.appLanguage).prefix(2)) \(SchichtaCore.formatGermanDate(day).prefix(6))"
    }

}
