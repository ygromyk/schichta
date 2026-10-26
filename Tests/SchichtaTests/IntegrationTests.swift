import AppKit
import Foundation
import Testing
@testable import Schichta

@Suite("Subprocesses")
struct ShellTests {
    @Test func passesEnvironment() throws {
        var env = ProcessInfo.processInfo.environment
        env["SCHICHTA_TOTAL_HHMM"] = "02:00"
        let output = try Shell.run("/bin/zsh", ["-c", "echo $SCHICHTA_TOTAL_HHMM"], environment: env, timeout: 10)
        #expect(output.text.trimmingCharacters(in: .whitespacesAndNewlines) == "02:00")
    }

    @Test("A command that never reads a large stdin neither hangs nor raises SIGPIPE")
    func largeUnreadStdin() throws {
        let input = Data(repeating: UInt8(ascii: "x"), count: 1_000_000)
        let ignored = try Shell.run("/bin/zsh", ["-c", "echo ok"], stdin: input, timeout: 10)
        #expect(ignored.status == 0 && ignored.text == "ok\n")
        let echoed = try Shell.run("/bin/cat", [], stdin: input, timeout: 10)
        #expect(echoed.stdout == input)
    }
}

@Suite("App shell")
struct AppShellTests {
    @Test func iconHasRequestedSize() {
        let icon = AppIconGenerator.makeIcon(size: 128)
        #expect(icon.size == NSSize(width: 128, height: 128))
    }

    @Test func activeScreenHasASize() {
        let screen = AppDelegate.activeScreen()
        #expect(screen.frame.width > 0 && screen.frame.height > 0)
    }

    @Test func notificationCarriesTheAppIcon() throws {
        let content = AppDelegate.makeNotificationContent(title: "Schichta Test", subtitle: "Check-in", body: "Was machst du gerade?", soundEnabled: true)
        #expect(content.title == "Schichta Test")
        #expect(content.subtitle == "Check-in")
        #expect(content.body == "Was machst du gerade?")
        #expect(content.sound != nil)
        let attachment = try #require(content.attachments.first)
        #expect(content.attachments.count == 1 && attachment.identifier == "schichta-icon")
        #expect(FileManager.default.fileExists(atPath: AppDelegate.notificationIconURL.path))
    }
}

@Suite("Booking targets")
struct BookingTargetTests {
    let entries = [
        Entry(id: "a", date: "2026-10-26", ticket: "PROJ-1", description: "Review", minutes: 90, estimated: false),
        Entry(id: "b", date: "2026-10-26", ticket: "PROJ-2", description: "Fix", minutes: 30, estimated: true),
    ]

    func prepare(_ json: String, secret: @escaping (String) -> String? = { _ in nil }) throws -> [PreparedRequest] {
        let target = try BookingTarget.parse(id: "test", data: Data(json.utf8))
        return try TargetRenderer.prepare(target: target, day: "2026-10-26", entries: entries, author: "Max Mustermann",
                                          workStart: (9, 0), repos: [], secret: secret)
    }

    @Test func perEntryRequestsRenderPlaceholdersAndAuth() throws {
        let requests = try prepare("""
        {"name":"Test","url":"https://example.test/api/{{entry.ticket}}/x","mode":"perEntry",
         "auth":{"type":"bearer","secret":"t1"},
         "headers":{"X-Day":"{{date}}"},
         "body":{"minutes":"{{entry.minutes}}","hours":"{{entry.hours}}","text":"{{entry.ticket}} {{entry.description}}",
                 "task":"{{map.ticket}}","start":"{{entry.start}}","end":"{{entry.end}}","est":"{{entry.estimated}}"},
         "map":{"PROJ-1":"task-9","PROJ-2":"task-8"}}
        """, secret: { $0 == "t1" ? "s3cr3t" : nil })
        #expect(requests.count == 2)
        #expect(requests[0].url.absoluteString == "https://example.test/api/PROJ-1/x")
        #expect(requests[0].headers["Authorization"] == "Bearer s3cr3t")
        #expect(requests[0].headers["X-Day"] == "2026-10-26")

        let body0 = try #require(try JSONSerialization.jsonObject(with: requests[0].body) as? [String: Any])
        #expect(body0["minutes"] as? Int == 90, "a lone placeholder keeps its number type")
        #expect(body0["hours"] as? Double == 1.5)
        #expect(body0["text"] as? String == "PROJ-1 Review")
        #expect(body0["task"] as? String == "task-9")
        #expect(body0["start"] as? String == "2026-10-26T08:00:00Z", "09:00 Berlin (CET) = 08:00 UTC")
        #expect(body0["end"] as? String == "2026-10-26T09:30:00Z")
        #expect(body0["est"] as? Bool == false)

        let body1 = try #require(try JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any])
        #expect(body1["start"] as? String == "2026-10-26T09:30:00Z", "entries are laid out back to back")
        #expect(!requests[0].previewText.contains("s3cr3t") && requests[0].previewText.contains("Authorization: ••••••"))
    }

    @Test func perDayRequestCarriesAllEntries() throws {
        let requests = try prepare(#"{"url":"http://127.0.0.1:9/hook","mode":"perDay","body":{"entries":"{{entries}}","total":"{{totalMinutes}}","who":"{{author}}"}}"#)
        #expect(requests.count == 1)
        let body = try #require(try JSONSerialization.jsonObject(with: requests[0].body) as? [String: Any])
        #expect((body["entries"] as? [Any])?.count == 2 && body["total"] as? Int == 120)
    }

    @Test("Invalid targets are rejected", arguments: [
        #"{"url":"https://a.test","auth":{"type":"bearer","secret":"t1"},"body":{}}"#,     // secret missing from Keychain
        #"{"url":"https://a.test","body":{"x":"{{entry.nope}}"}}"#,                        // unknown placeholder
        #"{"url":"https://a.test","body":{"x":"{{map.ticket}}"},"map":{"PROJ-1":"1"}}"#,   // no map entry for PROJ-2
        #"{"url":"http://a.test/x","body":{}}"#,                                           // plain http to a remote host
        #"{"url":"https://a.test","auth":{"type":"bearer","secret":"n","token":"abc"}}"#,  // plaintext secret in the file
    ])
    func rejectsInvalidTargets(json: String) {
        #expect(throws: (any Error).self) { try prepare(json) }
    }

    @Test func bundledClockifyExampleParses() throws {
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("targets/clockify.example.json")
        let parsed = try BookingTarget.parse(id: "clockify", data: Data(contentsOf: example))
        #expect(parsed.auth == .header(name: "X-Api-Key", secret: "clockify-api-key"))
    }
}

@Suite("AI summary")
struct AISummaryTests {
    @Test func redactorRemovesSecretsButKeepsTickets() {
        let redacted = SecretRedactor.redact("password=hunter2 und Bearer abc.def-123 und token: xyz sowie ghp_abcdefghijklmnopqrstuvwxyz12 bleibt PROJ-12")
        for secret in ["hunter2", "abc.def-123", "xyz", "ghp_"] {
            #expect(!redacted.contains(secret), "\(secret) must be removed")
        }
        #expect(redacted.contains("PROJ-12") && redacted.contains("password=[ENTFERNT]"))
    }

    @Test func parsesTheFirstJSONObjectOfAnAnswer() throws {
        let answer = """
        Hier ist das Ergebnis:
        ```json
        {"summary":"Review und Fix.","entries":[{"ticket":"proj-1","description":"Review","minutes":90,"evidence":"Notiz"},
         {"ticket":"","description":"Abstimmung","minutes":null,"evidence":"Chat"},{"ticket":"","description":"  ","minutes":5}],
         "questions":["Wie lange Abstimmung?"]}
        ```
        """
        let result = try AISummary.parse(answer)
        #expect(result.summary == "Review und Fix.")
        #expect(result.proposals.count == 2, "entries with an empty description are dropped")
        #expect(result.proposals[0].ticket == "PROJ-1" && result.proposals[0].minutes == 90 && result.proposals[0].estimated)
        #expect(result.proposals[1].minutes == 0 && result.proposals[1].source.contains("Zeit offen"))
        #expect(result.proposals.allSatisfy { $0.id.hasPrefix("ai-") })
        #expect(result.questions == ["Wie lange Abstimmung?"])
        #expect(throws: (any Error).self) { try AISummary.parse("kein json") }
    }

    @Test func readsChatsOnlyFromTrackedRepos() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("schichta-chat-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let claudeDir = home.appendingPathComponent(".claude/projects/-work-app")
        let codexDir = home.appendingPathComponent(".codex/sessions/2026/10/26")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try [
            #"{"type":"user","timestamp":"2026-10-26T08:00:00.000Z","cwd":"/work/app/sub","gitBranch":"feature/x","message":{"role":"user","content":"Fix den Login-Bug token=geheim123"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-26T08:05:00.000Z","cwd":"/work/app/sub","message":{"role":"assistant","content":[]}}"#,
            #"{"type":"user","timestamp":"2026-10-26T08:09:00.000Z","cwd":"/work/app/sub","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}"#,
            #"{"type":"user","timestamp":"2026-10-26T08:10:00.000Z","cwd":"/work/app/sub","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
            #"{"type":"user","timestamp":"2026-10-26T09:30:00.000Z","cwd":"/work/app/sub","message":{"role":"user","content":[{"type":"text","text":"Tests ergänzen"}]}}"#,
            #"{"type":"user","timestamp":"2026-10-25T09:30:00.000Z","cwd":"/work/app","message":{"role":"user","content":"Gestern"}}"#,
        ].joined(separator: "\n").write(to: claudeDir.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)
        try #"{"type":"user","timestamp":"2026-10-26T10:00:00Z","cwd":"/private/hobby","message":{"role":"user","content":"Privat"}}"#
            .write(to: claudeDir.appendingPathComponent("s2.jsonl"), atomically: true, encoding: .utf8)
        try [
            #"{"timestamp":"2026-10-26T11:00:00.000Z","type":"session_meta","payload":{"cwd":"/work/app","git":{"branch":"main"}}}"#,
            #"{"timestamp":"2026-10-26T11:00:05.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}"#,
            #"{"timestamp":"2026-10-26T11:00:06.000Z","type":"event_msg","payload":{"type":"user_message","message":"Refactoring Service"}}"#,
            #"{"timestamp":"2026-10-26T11:04:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"ok"}}"#,
        ].joined(separator: "\n").write(to: codexDir.appendingPathComponent("rollout-1.jsonl"), atomically: true, encoding: .utf8)

        let repo = TrackedRepo(path: "/work/app", projectName: "App", defaultTicket: "", enabled: true)
        let chats = ChatActivity.read(day: "2026-10-26", repos: [repo], home: home)
        try #require(chats.count == 2, "one Claude and one Codex session; the private repo is excluded")

        let claude = chats[0]
        #expect(claude.tool == "Claude Code" && claude.project == "App" && claude.branch == "feature/x")
        #expect(claude.prompts.count == 2 && claude.prompts[1] == "Tests ergänzen", "tool results and commands are not prompts")
        #expect(!claude.prompts[0].contains("geheim123"), "prompts are redacted")
        #expect(claude.activeMinutes == 10, "a gap over 10 minutes does not count as active")
        #expect(chats[1].tool == "Codex" && chats[1].branch == "main" && chats[1].prompts == ["Refactoring Service"])

        #expect(ChatActivity.read(day: "2026-10-26", repos: [], home: home).isEmpty)
        let evidence = ChatActivity.formatEvidence(chats)
        #expect(evidence.contains("Claude Code · App (feature/x) · 09:00–10:30"), "times in the app's time zone")
    }

    @Test func builtInToolsAreLockedDown() {
        let tools = AITools.builtIns()
        #expect(tools.map(\.id) == ["claude", "codex", "ollama"])
        #expect(tools[0].command.contains("--tools \"\""), "Claude runs without tools")
        #expect(tools[1].command.contains("read-only"), "Codex runs read-only")
    }

    @Test func customToolFilesAreLoaded() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("schichta-ai-tools-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"name":"Mein LLM","command":"llm -m x"}"#.write(to: dir.appendingPathComponent("llm.json"), atomically: true, encoding: .utf8)
        try #"{"name":"kaputt"}"#.write(to: dir.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)

        let loaded = AITools.load(folder: dir)
        #expect(loaded.tools.count == 4, "three built-ins plus llm.json; the example file is ignored")
        #expect(loaded.tools.last?.id == "file:llm" && loaded.tools.last?.command == "llm -m x")
        #expect(loaded.errors.count == 1 && loaded.errors[0].contains("broken.json"))
    }
}
