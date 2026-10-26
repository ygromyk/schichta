import Foundation

// MARK: - KI-Zusammenfassung (Chat-Belege + frei konfigurierbarer CLI-Befehl)
//
// Die App kennt keinen KI-Anbieter: Sie baut den Auftrag (Notizen, Git, Chat-Belege, bereits
// Erfasstes), zeigt ihn als Vorschau und schickt ihn erst nach Klick per stdin an den
// eingestellten Befehl (z. B. `claude -p`). Die JSON-Antwort wird zu bearbeitbaren Vorschlägen.

struct ChatSession: Equatable {
    let tool: String
    let project: String
    let branch: String
    let start: Date
    let end: Date
    let activeMinutes: Int
    let prompts: [String]
}

enum SecretRedactor {
    private static let rules: [(NSRegularExpression, String)] = [
        (#"(?i)\b(pass(word|wort)?|pwd|token|secret|api[_-]?key|client[_-]?secret)\b(\s*[:=]\s*)\S+"#, "$1$3[ENTFERNT]"),
        (#"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer [ENTFERNT]"),
        (#"\b(sk|pk|rk)-[A-Za-z0-9_-]{16,}"#, "[ENTFERNT]"),
        (#"\bgh[pousr]_[A-Za-z0-9]{20,}"#, "[ENTFERNT]"),
        (#"\bAKIA[0-9A-Z]{16}\b"#, "[ENTFERNT]"),
        (#"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#, "[ENTFERNT]"),
        (#"[A-Za-z0-9+/_-]{40,}={0,2}"#, "[ENTFERNT]")
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// Entfernt offensichtliche Geheimnisse (Passwörter, Tokens, lange Schlüssel). Kein Ersatz für Sorgfalt, nur ein Netz.
    static func redact(_ text: String) -> String {
        rules.reduce(text) { result, rule in
            rule.0.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: rule.1)
        }
    }
}

enum ChatActivity {
    /// Pausen über 10 Minuten zählen nicht als aktive Chat-Zeit.
    static let idleCutoff: TimeInterval = 10 * 60
    static let maxPromptsPerSession = 20
    static let maxPromptLength = 300

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parseDate(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    static func dayRange(_ day: String) -> (Date, Date) {
        let start = AppTime.calendar.startOfDay(for: SchichtaCore.date(fromDay: day))
        return (start, AppTime.calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    /// Liest Claude-Code- und Codex-Sitzungen des Tages, aber nur aus getrackten Repositories
    /// (private Projekte bleiben außen vor).
    static func read(day: String, repos: [TrackedRepo], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ChatSession] {
        let enabled = repos.filter(\.enabled)
        guard !enabled.isEmpty else { return [] }
        let (start, end) = dayRange(day)
        let project: (String) -> String? = { cwd in
            enabled.first(where: { cwd == $0.path || cwd.hasPrefix($0.path + "/") })?.displayLabel
        }
        let claude = claudeFiles(home: home, since: start).compactMap { parseClaude($0, start: start, end: end, project: project) }
        let codex = codexFiles(home: home, day: day, since: start).compactMap { parseCodex($0, start: start, end: end, project: project) }
        return (claude + codex).sorted { $0.start < $1.start }
    }

    private static func modifiedSince(_ url: URL, _ date: Date) -> Bool {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= date
    }

    private static func claudeFiles(home: URL, since: Date) -> [URL] {
        let root = home.appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        let projects = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return projects.flatMap { dir in
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == "jsonl" && modifiedSince($0, since) }
        }
    }

    private static func codexFiles(home: URL, day: String, since: Date) -> [URL] {
        // Codex legt Sitzungen nach Startdatum ab; Sitzungen über Mitternacht liegen im Vortag.
        let fm = FileManager.default
        let previous = SchichtaCore.day(from: since.addingTimeInterval(-3600))
        return [previous, day].flatMap { d -> [URL] in
            let dir = home.appendingPathComponent(".codex/sessions/" + d.replacingOccurrences(of: "-", with: "/"))
            return ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == "jsonl" && modifiedSince($0, since) }
        }
    }

    private static func jsonLines(_ url: URL) -> [[String: Any]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }
    }

    /// Echte Nutzereingaben: keine System-/Befehlshüllen wie <command-name> oder <environment_context>.
    private static func cleanPrompt(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.hasPrefix("<"), !t.hasPrefix("Caveat:") else { return nil }
        let single = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(SecretRedactor.redact(single).prefix(maxPromptLength))
    }

    private static func session(tool: String, project: String, branch: String, times: [Date], prompts: [String]) -> ChatSession? {
        let sorted = times.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let active = zip(sorted, sorted.dropFirst()).reduce(0.0) { sum, pair in
            let gap = pair.1.timeIntervalSince(pair.0)
            return sum + (gap <= idleCutoff ? gap : 0)
        }
        var seen = Set<String>()
        let unique = prompts.filter { seen.insert($0).inserted }
        return ChatSession(tool: tool, project: project, branch: branch, start: first, end: last,
                           activeMinutes: Int((active / 60).rounded()), prompts: Array(unique.prefix(maxPromptsPerSession)))
    }

    static func parseClaude(_ url: URL, start: Date, end: Date, project: (String) -> String?) -> ChatSession? {
        var times: [Date] = []
        var prompts: [String] = []
        var cwd = ""
        var branch = ""
        for line in jsonLines(url) {
            guard let ts = parseDate(line["timestamp"]), ts >= start, ts < end else { continue }
            if line["isSidechain"] as? Bool == true { continue }
            times.append(ts)
            if cwd.isEmpty, let c = line["cwd"] as? String { cwd = c }
            if branch.isEmpty, let b = line["gitBranch"] as? String { branch = b }
            guard line["type"] as? String == "user", line["isMeta"] as? Bool != true,
                  let message = line["message"] as? [String: Any] else { continue }
            if let text = message["content"] as? String {
                if let p = cleanPrompt(text) { prompts.append(p) }
            } else if let items = message["content"] as? [[String: Any]] {
                for item in items where item["type"] as? String == "text" {
                    if let p = cleanPrompt(item["text"] as? String ?? "") { prompts.append(p) }
                }
            }
        }
        guard let name = project(cwd) else { return nil }
        return session(tool: "Claude Code", project: name, branch: branch, times: times, prompts: prompts)
    }

    static func parseCodex(_ url: URL, start: Date, end: Date, project: (String) -> String?) -> ChatSession? {
        var times: [Date] = []
        var eventPrompts: [String] = []
        var itemPrompts: [String] = []
        var cwd = ""
        var branch = ""
        for line in jsonLines(url) {
            let payload = line["payload"] as? [String: Any] ?? [:]
            if cwd.isEmpty, let c = payload["cwd"] as? String { cwd = c }
            if branch.isEmpty, let b = (payload["git"] as? [String: Any])?["branch"] as? String { branch = b }
            guard let ts = parseDate(line["timestamp"]), ts >= start, ts < end else { continue }
            times.append(ts)
            switch (line["type"] as? String, payload["type"] as? String) {
            case ("event_msg", "user_message"):
                if let p = cleanPrompt(payload["message"] as? String ?? "") { eventPrompts.append(p) }
            case ("response_item", "message") where payload["role"] as? String == "user":
                for item in payload["content"] as? [[String: Any]] ?? [] {
                    if let p = cleanPrompt(item["text"] as? String ?? "") { itemPrompts.append(p) }
                }
            default:
                break
            }
        }
        guard let name = project(cwd) else { return nil }
        return session(tool: "Codex", project: name, branch: branch, times: times,
                       prompts: eventPrompts.isEmpty ? itemPrompts : eventPrompts)
    }

    static func formatEvidence(_ sessions: [ChatSession]) -> String {
        guard !sessions.isEmpty else { return "(keine Chat-Sitzungen in getrackten Repositories)" }
        return sessions.map { s in
            let head = "\(s.tool) · \(s.project)\(s.branch.isEmpty ? "" : " (\(s.branch))") · \(AppTime.clock.string(from: s.start))–\(AppTime.clock.string(from: s.end)) · aktiv ca. \(SchichtaCore.formatTime(s.activeMinutes)) h"
            return ([head] + s.prompts.map { "  - \($0)" }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
