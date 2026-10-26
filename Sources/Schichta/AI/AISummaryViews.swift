import AppKit
import SwiftUI

@MainActor
final class AISummaryModel: ObservableObject {
    enum Phase: Equatable {
        case idle, preparing, ready, running, failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var prompt: String = ""
    @Published var sessionCount: Int = 0

    func prepare(store: SchichtaStore) {
        phase = .preparing
        let day = store.selectedDay
        let repos = store.trackedRepos
        let author = store.gitAuthorFilter
        let notes = store.journalForSelectedDay().notes
        let existing = store.entriesForSelectedDay()
        Task.detached {
            let gitText = (try? Activity.readRepos(day, repos: repos, authorFilter: author)).map(Activity.formatLogText) ?? ""
            let sessions = ChatActivity.read(day: day, repos: repos)
            let prompt = AISummary.prompt(day: day, notes: notes, gitText: gitText,
                                          chatText: ChatActivity.formatEvidence(sessions), existing: existing)
            await MainActor.run {
                self.prompt = prompt
                self.sessionCount = sessions.count
                self.phase = .ready
            }
        }
    }

    func send(store: SchichtaStore, onDone: @escaping () -> Void) {
        let command = store.aiCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            phase = .failed("Kein KI-Befehl eingerichtet (Einstellungen › Integrationen).")
            return
        }
        phase = .running
        let prompt = self.prompt
        let day = store.selectedDay
        Task.detached {
            do {
                let result = try AISummary.parse(try AISummary.run(command: command, prompt: prompt))
                await MainActor.run {
                    store.applyAISummary(result, day: day)
                    self.phase = .idle
                    onDone()
                }
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }
}

struct AISummarySheet: View {
    @ObservedObject var store: SchichtaStore
    @StateObject private var model = AISummaryModel()
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(store.t("KI-Zusammenfassung für \(SchichtaCore.formatGermanDate(store.selectedDay))", "AI summary for \(SchichtaCore.formatGermanDate(store.selectedDay))"), systemImage: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            Text(store.t("Genau dieser Text wird per stdin an den eingestellten Befehl geschickt. Offensichtliche Geheimnisse sind bereits entfernt.",
                         "Exactly this text is sent via stdin to the configured command. Obvious secrets are already removed."))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text(store.aiCommand.isEmpty ? store.t("Kein Befehl eingerichtet", "No command set up") : store.aiCommand)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundColor(.secondary)

            Group {
                switch model.phase {
                case .preparing:
                    ProgressView(store.t("Git und Chats werden gelesen…", "Reading Git and chats…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    ScrollView {
                        Text(model.prompt)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
            }
            .frame(maxHeight: .infinity)

            if case .failed(let message) = model.phase {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(store.t("\(model.sessionCount) Chat-Sitzung(en) · \(model.prompt.count) Zeichen", "\(model.sessionCount) chat session(s) · \(model.prompt.count) characters"))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                Spacer()
                if model.phase == .running {
                    ProgressView().controlSize(.small)
                }
                Button(store.t("Einstellungen…", "Settings…")) {
                    isPresented = false
                    appDelegate()?.showSettings(tab: 3)
                }
                Button(store.t("Abbrechen", "Cancel")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(store.t("Senden", "Send")) {
                    model.send(store: store) { isPresented = false }
                }
                .prominentWhenEnabled(model.phase == .ready || {
                    if case .failed = model.phase { return !model.prompt.isEmpty }
                    return false
                }())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720, height: 560)
        .onAppear { model.prepare(store: store) }
    }
}

struct AISettingsSection: View {
    @ObservedObject var store: SchichtaStore
    @State private var tools: [AITool] = []
    @State private var toolErrors: [String] = []

    private func reload() {
        (tools, toolErrors) = AITools.load()
    }

    var body: some View {
        GroupBox(label: Label(store.t("KI-Zusammenfassung", "AI Summary"), systemImage: "wand.and.stars")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.t("Befehl, der den Tagesauftrag auf stdin bekommt und JSON ausgibt. Die App ruft keine KI-API direkt auf; Chats werden nur aus getrackten Repositories gelesen. Vor dem Senden siehst du immer den vollständigen Text.",
                             "Command that receives the day request on stdin and prints JSON. The app never calls an AI API directly; chats are only read from tracked repositories. You always see the full text before sending."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(store.t("z. B. claude -p …", "e.g. claude -p …"), text: $store.aiCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onChange(of: store.aiCommand) {
                        // Von Hand geändert: nicht mehr die Vorlage, sondern ein eigener Befehl.
                        if tools.first(where: { $0.id == store.aiToolId })?.command != store.aiCommand { store.aiToolId = "" }
                    }
                HStack(spacing: 8) {
                    Picker(store.t("Werkzeug:", "Tool:"), selection: Binding(
                        get: { tools.contains(where: { $0.id == store.aiToolId }) ? store.aiToolId : "" },
                        set: { id in
                            store.aiToolId = id
                            if let tool = tools.first(where: { $0.id == id }) { store.aiCommand = tool.command }
                        }
                    )) {
                        Text(store.t("Eigener Befehl", "Custom command")).tag("")
                        ForEach(tools) { tool in
                            Text(tool.name + (tool.isBuiltIn ? "" : store.t(" (eigene Datei)", " (custom file)"))
                                 + (tool.installed ? "" : store.t(" – nicht gefunden", " – not found")))
                                .tag(tool.id)
                        }
                    }
                    .frame(maxWidth: 360)
                    Spacer()
                    Button(store.t("Ordner für eigene Tools", "Custom tools folder")) { NSWorkspace.shared.open(AITools.folder) }
                    Button(store.t("Neu laden", "Reload")) { reload() }
                }
                ForEach(toolErrors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { reload() }
    }
}
