import AppKit
import SwiftUI

/// Books every open day of a week to one booking target: preview all days first, then send in one go.
/// Same rules as booking one day: only what was previewed is sent, and days with unconfirmed estimates are skipped.
@MainActor
final class WeekBookingModel: ObservableObject {
    struct DayPlan: Identifiable {
        let day: String
        let minutes: Int
        let signature: String
        let requests: [PreparedRequest]
        /// Why this day is not sent (estimates, render error); nil = ready.
        let skipReason: String?
        var result: String? = nil
        var sent = false
        var id: String { day }
    }

    @Published var targets: [BookingTargetsModel.Loaded] = []
    @Published var targetId = ""
    @Published var plans: [DayPlan] = []
    @Published var isSending = false
    private let sender = TargetSender()

    var readyPlans: [DayPlan] { plans.filter { $0.skipReason == nil && !$0.sent } }

    func load() {
        targets = BookingTargetsModel.loadTargets().filter { $0.target != nil }
        if !targets.contains(where: { $0.id == targetId }) { targetId = targets.first?.id ?? "" }
    }

    /// Previews every past or current day of the week that has entries and isn't booked yet.
    func prepare(store: SchichtaStore, week: WeekSummary, today: String = SchichtaCore.day()) {
        guard let target = targets.first(where: { $0.id == targetId })?.target else {
            plans = []
            return
        }
        plans = week.days.filter { !$0.booked && $0.minutes > 0 && $0.day <= today }.map { day in
            let entries = store.database.entries.filter { $0.date == day.day }
            let signature = BookingTargetsModel.signature(entries)
            if day.estimatedCount > 0 {
                return DayPlan(day: day.day, minutes: day.minutes, signature: signature, requests: [],
                               skipReason: store.t("\(day.estimatedCount) Schätzung(en) erst bestätigen", "confirm \(day.estimatedCount) estimate(s) first"))
            }
            do {
                let requests = try TargetRenderer.prepare(
                    target: target, day: day.day, entries: entries, author: store.gitAuthorFilter,
                    workStart: (store.workStartHour, store.workStartMinute), repos: store.trackedRepos,
                    secret: TargetSecrets.get)
                return DayPlan(day: day.day, minutes: day.minutes, signature: signature, requests: requests, skipReason: nil)
            } catch {
                return DayPlan(day: day.day, minutes: day.minutes, signature: signature, requests: [], skipReason: store.describe(error))
            }
        }
    }

    /// Sends the ready days one after another; a day counts as booked only if all its requests succeed.
    func send(store: SchichtaStore) {
        isSending = true
        Task {
            for index in plans.indices where plans[index].skipReason == nil && !plans[index].sent {
                let day = plans[index].day
                let current = BookingTargetsModel.signature(store.database.entries.filter { $0.date == day })
                guard current == plans[index].signature else {
                    plans[index].result = store.t("Einträge geändert – Vorschau neu erzeugen", "Entries changed – preview again")
                    continue
                }
                let results = await sender.send(plans[index].requests)
                let okCount = results.filter(\.ok).count
                plans[index].result = "\(okCount)/\(results.count) OK\n" + results.map(\.line).joined(separator: "\n")
                if okCount == results.count {
                    plans[index].sent = true
                    store.markDayBooked(day, booked: true)
                }
            }
            isSending = false
        }
    }
}

struct WeekBookingSheet: View {
    @ObservedObject var store: SchichtaStore
    let week: WeekSummary
    @Binding var isPresented: Bool
    @StateObject private var model = WeekBookingModel()
    @State private var confirmSend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.t("Woche buchen · KW \(week.weekNumber)", "Book week · W\(week.weekNumber)"))
                    .font(.system(size: 15, weight: .bold))

                if model.targets.isEmpty {
                    Text(store.t("Noch kein Buchungsziel eingerichtet. Lege eine Target-Datei an (Hauptfenster › Buchen in …).",
                                 "No booking target set up yet. Add a target file (main window › Book in …)."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Text(store.t("Ziel:", "Target:"))
                            .font(.system(size: 12, weight: .medium))
                        Picker("", selection: $model.targetId) {
                            ForEach(model.targets) { loaded in
                                Text(loaded.target?.name ?? loaded.id).tag(loaded.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 260)
                        .disabled(model.isSending)
                        Spacer()
                    }

                    if model.plans.isEmpty {
                        Text(store.t("Keine offenen Tage mit Einträgen in dieser Woche.", "No open days with entries this week."))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.plans) { plan in
                        dayPlanRow(plan)
                    }
                }
                .padding(.horizontal, 20)
            }

            Divider()
            HStack {
                if model.isSending { ProgressView().controlSize(.small) }
                Spacer()
                Button(store.t("Schließen", "Close")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(store.t("\(model.readyPlans.count) Tag(e) senden …", "Send \(model.readyPlans.count) day(s) …")) { confirmSend = true }
                    .buttonStyle(.borderedProminent)
                    .tint(SchichtaTheme.forestGreen)
                    .disabled(model.readyPlans.isEmpty || model.isSending)
            }
            .padding(12)
        }
        .frame(width: 680, height: 560)
        .onAppear {
            model.load()
            model.prepare(store: store, week: week)
        }
        .onChange(of: model.targetId) { model.prepare(store: store, week: week) }
        .alert(store.t("Jetzt senden?", "Send now?"), isPresented: $confirmSend) {
            Button(store.t("Abbrechen", "Cancel"), role: .cancel) {}
            Button(store.t("Senden", "Send")) { model.send(store: store) }
        } message: {
            let requests = model.readyPlans.reduce(0) { $0 + $1.requests.count }
            Text(store.t("\(requests) Anfrage(n) für \(model.readyPlans.count) Tag(e) werden genau wie in der Vorschau gesendet. Erfolgreiche Tage werden als gebucht markiert.",
                         "\(requests) request(s) for \(model.readyPlans.count) day(s) will be sent exactly as previewed. Successful days are marked as booked."))
        }
    }

    private func dayPlanRow(_ plan: WeekBookingModel.DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: plan.sent ? "checkmark.circle.fill" : (plan.skipReason == nil ? "paperplane" : "exclamationmark.triangle"))
                    .foregroundColor(plan.sent ? SchichtaTheme.forestGreen : (plan.skipReason == nil ? .blue : .orange))
                Text("\(SchichtaCore.weekdayName(plan.day, language: store.appLanguage)) \(SchichtaCore.formatGermanDate(plan.day))")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(SchichtaCore.formatTime(plan.minutes))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(plan.sent ? store.t("Gebucht ✓", "Booked ✓")
                     : plan.skipReason ?? store.t("\(plan.requests.count) Anfrage(n) bereit", "\(plan.requests.count) request(s) ready"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(plan.skipReason == nil ? .secondary : .orange)
                    .lineLimit(1)
            }
            if plan.skipReason == nil && !plan.requests.isEmpty {
                DisclosureGroup(store.t("Vorschau", "Preview")) {
                    Text(plan.requests.map(\.previewText).joined(separator: "\n\n———\n\n"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                }
                .font(.system(size: 11))
            }
            if let result = plan.result {
                Text(result)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundColor(plan.sent ? .secondary : .orange)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }
}
