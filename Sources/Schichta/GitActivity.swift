import Foundation

// MARK: - Git & Activity Log Reader

enum Activity {
    /// First and last second of `day` as ISO timestamps for `git --since/--until`.
    static func bounds(_ day: String, in time: AppTime.State = AppTime.state) throws -> (String, String) {
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let start = time.day.date(from: day), time.day.string(from: start) == day else {
            throw SchichtaError("Ungültiges Datum")
        }
        let end = time.calendar.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
        return (time.isoSeconds.string(from: start), time.isoSeconds.string(from: end))
    }

    /// Git-Autor aus `git config user.name`, damit kein Name im Code steht.
    static func gitUserName() -> String {
        guard let output = try? Shell.run("/usr/bin/git", ["config", "--global", "user.name"], timeout: 5) else { return "" }
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func git(_ repo: URL, _ arguments: [String]) -> [String: Any] {
        guard let output = try? Shell.run("/usr/bin/git", ["-C", repo.path] + arguments, timeout: 15) else {
            return ["error": "Git konnte nicht gestartet werden."]
        }
        guard output.status == 0 else { return ["error": "Git-Abfrage fehlgeschlagen oder Zeitlimit überschritten."] }
        let text = output.text
        return ["text": String(text.prefix(100000)), "truncated": text.count > 100000]
    }

    static func readRepos(_ day: String, repos: [TrackedRepo], authorFilter: String?) throws -> [String: Any] {
        let (start, end) = try bounds(day)
        let author = (authorFilter ?? gitUserName()).trimmingCharacters(in: .whitespacesAndNewlines)
        let authorArg = author.isEmpty ? "--all" : "--author=\(author)"
        let isToday = (day == SchichtaCore.day())

        var repoResults: [[String: Any]] = []

        for repo in repos {
            guard repo.enabled else { continue }
            let repoURL = URL(fileURLWithPath: repo.path)
            var repoDict: [String: Any] = [
                "repository": repo.folderName,
                "projectName": repo.projectName,
                "displayLabel": repo.displayLabel,
                "defaultTicket": repo.defaultTicket,
                "path": repo.path,
                "enabled": repo.enabled
            ]

            guard FileManager.default.fileExists(atPath: repoURL.path) else {
                repoDict["error"] = "Verzeichnis nicht gefunden: \(repo.path)"
                repoResults.append(repoDict)
                continue
            }

            let isInsideGit = git(repoURL, ["rev-parse", "--is-inside-work-tree"])
            if (isInsideGit["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) != "true" {
                repoDict["error"] = "Kein Git-Repository unter: \(repo.path)"
                repoResults.append(repoDict)
                continue
            }

            // 1. Eigene Commits
            let commits = git(repoURL, ["log", "--all", "--since-as-filter=\(start)", "--until=\(end)", authorArg, "-n", "150", "--format=%h | Autorzeit: %aI | Commitzeit: %cI | %s"])
            repoDict["commits"] = commits

            // 2. Geänderte Dateien / Diff-Statistik
            let changedFiles = git(repoURL, ["log", "--all", "--since-as-filter=\(start)", "--until=\(end)", authorArg, "--shortstat", "--oneline", "-n", "30"])
            repoDict["changed_files"] = changedFiles

            // 3. Lokale Branch-/HEAD-Aktivitäten
            let head = git(repoURL, ["reflog", "show", "HEAD", "--since=\(start)", "--until=\(end)", "-n", "200", "--date=iso-strict", "--format=%gD | %gs"])
            repoDict["head_activity"] = head

            // 4. Uncommitted Working-Tree-Änderungen (falls heute)
            if isToday {
                let wt = git(repoURL, ["status", "--short"])
                repoDict["working_tree"] = wt
            } else {
                repoDict["working_tree"] = ["text": ""]
            }

            repoResults.append(repoDict)
        }

        return [
            "date": day,
            "timezone": AppTime.timeZone.identifier,
            "repositories": repoResults,
            "scope": "Direkt aus der Desktop-App gelesen, ohne Server. Lokale Git-Referenzen; kein Fetch. Eigene Commits, Diff-Statistik, Reflogs und Working-Tree je Tracked-Repository."
        ]
    }

    static func formatLogText(_ result: [String: Any]) -> String {
        let scope = result["scope"] as? String ?? ""
        guard let repos = result["repositories"] as? [[String: Any]] else { return scope }
        var parts: [String] = [scope]
        func appendGitSection(_ title: String, _ value: Any?) {
            let result = value as? [String: Any] ?? [:]
            parts.append(title)
            if let err = result["error"] as? String { parts.append(err) }
            else if let text = result["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(text) }
            else { parts.append("(keine gefunden)") }
            if (result["truncated"] as? Bool) == true { parts.append("(Ausgabe gekürzt)") }
        }
        func appendIfPresent(_ title: String, _ value: Any?) {
            let text = ((value as? [String: Any])?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            parts.append(title)
            parts.append(text)
        }
        for repo in repos {
            let name = repo["repository"] as? String ?? "Repo"
            let projectName = (repo["projectName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = !projectName.isEmpty ? "\(projectName) (\(name))" : name
            parts.append("\nREPOSITORY: \(title)")

            if let err = repo["error"] as? String {
                parts.append("Status: \(err)")
                continue
            }

            appendGitSection("Eigene Commits:", repo["commits"])
            appendIfPresent("Geänderte Dateien / Diff:", repo["changed_files"])
            appendIfPresent("Uncommittete Arbeitskopie (Heute):", repo["working_tree"])
            appendGitSection("Lokale HEAD-Aktivitäten:", repo["head_activity"])
        }
        return parts.joined(separator: "\n")
    }
}
