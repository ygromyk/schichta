import AppKit
import SwiftUI

@MainActor
final class BookingTargetsModel: ObservableObject {
    struct Loaded: Identifiable {
        let id: String
        let target: BookingTarget?
        let error: String?
    }

    struct Preview {
        let day: String
        let signature: String
        let requests: [PreparedRequest]
    }

    @Published var targets: [Loaded] = []
    @Published var secretSet: [String: Bool] = [:]
    @Published var previews: [String: Preview] = [:]
    @Published var messages: [String: String] = [:]
    @Published var sending: Set<String> = []
    private let sender = TargetSender()

    static var folder: URL {
        AppPaths.support.appendingPathComponent("targets", isDirectory: true)
    }

    /// Fingerprint of the day's entries: sending is only allowed while the preview still matches.
    static func signature(_ entries: [Entry]) -> String {
        entries.map { "\($0.id)|\($0.ticket)|\($0.description)|\($0.minutes)|\($0.estimated)|\($0.project)" }.joined(separator: "\n")
    }

    /// Reads every target file in the folder (an empty folder gets the example as a template).
    static func loadTargets() -> [Loaded] {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        // Empty folder: drop in the example as a template (*.example.json is never loaded).
        if files.isEmpty, let example = Bundle.main.url(forResource: "clockify.example", withExtension: "json") {
            try? fm.copyItem(at: example, to: folder.appendingPathComponent("clockify.example.json"))
        }
        return files
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".example.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let id = url.deletingPathExtension().lastPathComponent
                do {
                    return Loaded(id: id, target: try BookingTarget.parse(id: id, data: Data(contentsOf: url)), error: nil)
                } catch {
                    return Loaded(id: id, target: nil, error: error.localizedDescription)
                }
            }
    }

    func reload() {
        targets = Self.loadTargets()
        secretSet = targets.compactMap { $0.target?.auth.secretName }
            .reduce(into: [:]) { $0[$1] = TargetSecrets.exists($1) }
        previews = [:]
        messages = [:]
    }

    func saveSecret(_ name: String, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        secretSet[name] = TargetSecrets.set(name, trimmed)
    }

    func preview(_ id: String, store: SchichtaStore) {
        guard let target = targets.first(where: { $0.id == id })?.target else { return }
        let entries = store.entriesForSelectedDay()
        do {
            let requests = try TargetRenderer.prepare(
                target: target, day: store.selectedDay, entries: entries, author: store.gitAuthorFilter,
                workStart: (store.workStartHour, store.workStartMinute), repos: store.trackedRepos,
                secret: TargetSecrets.get
            )
            previews[id] = Preview(day: store.selectedDay, signature: Self.signature(entries), requests: requests)
            messages[id] = nil
        } catch {
            previews[id] = nil
            messages[id] = "✗ " + error.localizedDescription
        }
    }

    func isPreviewCurrent(_ id: String, store: SchichtaStore) -> Bool {
        guard let preview = previews[id] else { return false }
        return preview.day == store.selectedDay && preview.signature == Self.signature(store.entriesForSelectedDay())
    }

    func send(_ id: String, store: SchichtaStore) {
        guard isPreviewCurrent(id, store: store), let preview = previews[id] else { return }
        sending.insert(id)
        Task {
            let results = await sender.send(preview.requests)
            sending.remove(id)
            let okCount = results.filter(\.ok).count
            messages[id] = "\(okCount)/\(results.count) erfolgreich\n" + results.map(\.line).joined(separator: "\n")
        }
    }
}

struct BookingTargetsSection: View {
    @ObservedObject var store: SchichtaStore
    @StateObject private var model = BookingTargetsModel()
    @State private var secretInputs: [String: String] = [:]
    @State private var confirmSendId: String? = nil

    var body: some View {
        GroupBox(label: Label(store.t("booking.bookingTargetsTargetFiles"), systemImage: "paperplane")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.t("booking.eachJsonFileInThe"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(BookingTargetsModel.folder.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(store.t("booking.openFolder")) { NSWorkspace.shared.open(BookingTargetsModel.folder) }
                    Button(store.t("booking.reload")) { model.reload() }
                }

                if model.targets.isEmpty {
                    Text(store.t("booking.noTargetsYetCopyClockify"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                ForEach(model.targets) { loaded in
                    Divider()
                    targetRow(loaded)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { model.reload() }
        .alert(store.t("booking.sendNow"), isPresented: Binding(
            get: { confirmSendId != nil },
            set: { if !$0 { confirmSendId = nil } }
        )) {
            Button(store.t("booking.cancel"), role: .cancel) { confirmSendId = nil }
            Button(store.t("booking.send")) {
                if let id = confirmSendId { model.send(id, store: store) }
                confirmSendId = nil
            }
        } message: {
            let count = confirmSendId.flatMap { model.previews[$0]?.requests.count } ?? 0
            Text(store.t("booking.requestSWillBeSent", "\(count)"))
        }
    }

    @ViewBuilder
    private func targetRow(_ loaded: BookingTargetsModel.Loaded) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let target = loaded.target {
                HStack(spacing: 8) {
                    Text(target.name)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(target.mode == .perDay ? store.t("booking.perDay") : store.t("booking.perEntry"))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SchichtaTheme.forestGreen.opacity(0.12))
                        .cornerRadius(4)
                    Text("\(target.method) \(URL(string: target.url)?.host ?? target.url)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }

                if let secretName = target.auth.secretName {
                    let isSet = model.secretSet[secretName] == true
                    HStack(spacing: 8) {
                        Image(systemName: isSet ? "lock.fill" : "lock.open")
                            .foregroundColor(isSet ? SchichtaTheme.forestGreen : .orange)
                        Text(isSet ? store.t("booking.inKeychain", "\(secretName)")
                                   : store.t("booking.missing", "\(secretName)"))
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        SecureField(isSet ? store.t("booking.newValue") : store.t("booking.enterValue"), text: Binding(
                            get: { secretInputs[secretName] ?? "" },
                            set: { secretInputs[secretName] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        Button(store.t("booking.save")) {
                            model.saveSecret(secretName, secretInputs[secretName] ?? "")
                            secretInputs[secretName] = ""
                        }
                        .disabled((secretInputs[secretName] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                HStack(spacing: 8) {
                    Button(action: { model.preview(loaded.id, store: store) }) {
                        Label(store.t("booking.previewFor", "\(SchichtaCore.formatGermanDate(store.selectedDay))"), systemImage: "eye")
                    }
                    Button(action: { confirmSendId = loaded.id }) {
                        Label(store.t("booking.send2"), systemImage: "paperplane")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SchichtaTheme.forestGreen)
                    .disabled(!model.isPreviewCurrent(loaded.id, store: store) || model.sending.contains(loaded.id))
                    if model.sending.contains(loaded.id) {
                        ProgressView().controlSize(.small)
                    }
                }

                if let preview = model.previews[loaded.id] {
                    ScrollView {
                        Text(preview.requests.map(\.previewText).joined(separator: "\n\n———\n\n"))
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 220)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                    if !model.isPreviewCurrent(loaded.id, store: store) {
                        Text(store.t("booking.dayOrEntriesChangedRegenerate"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.orange)
                    }
                }
            } else {
                Label("\(loaded.id).json: \(loaded.error ?? "")", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

            if let message = model.messages[loaded.id] {
                Text(message)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
