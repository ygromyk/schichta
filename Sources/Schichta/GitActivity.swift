import Foundation

// MARK: - Git & Activity Log Reader

enum Activity {
    /// First and last second of `day` as ISO timestamps for `git --since/--until`.
    static func bounds(_ day: String, in time: AppTime.State = AppTime.state) throws -> (String, String) {
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let start = time.day.date(from: day), time.day.string(from: start) == day else {
            throw SchichtaError("Ungültiges Datum", en: "Invalid date")
        }
        let end = time.calendar.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
        return (time.isoSeconds.string(from: start), time.isoSeconds.string(from: end))
    }

    /// Git author from `git config user.name`, so no name is hard-coded.
    static func gitUserName() -> String {
        guard let output = try? Shell.run("/usr/bin/git", ["config", "--global", "user.name"], timeout: 5) else { return "" }
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func git(_ repo: URL, _ arguments: [String]) -> GitOutput {
        guard let output = try? Shell.run("/usr/bin/git", ["-C", repo.path] + arguments, timeout: 15) else {
            return GitOutput(error: LocalizedText("Git konnte nicht gestartet werden.", "Git could not be started."))
        }
        guard output.status == 0 else {
            return GitOutput(error: LocalizedText("Git-Abfrage fehlgeschlagen oder Zeitlimit überschritten.", "Git query failed or timed out."))
        }
        let text = output.text
        return GitOutput(text: String(text.prefix(100000)), truncated: text.count > 100000)
    }

    static func readRepos(_ day: String, repos: [TrackedRepo], authorFilter: String?) throws -> GitActivityResult {
        let (start, end) = try bounds(day)
        let author = (authorFilter ?? gitUserName()).trimmingCharacters(in: .whitespacesAndNewlines)
        let authorArg = author.isEmpty ? "--all" : "--author=\(author)"
        let isToday = (day == SchichtaCore.day())

        var repoResults: [RepoActivity] = []

        for repo in repos {
            guard repo.enabled else { continue }
            let repoURL = URL(fileURLWithPath: repo.path)
            var activity = RepoActivity(repo: repo)

            guard FileManager.default.fileExists(atPath: repoURL.path) else {
                activity.error = LocalizedText("Verzeichnis nicht gefunden: \(repo.path)", "Directory not found: \(repo.path)")
                repoResults.append(activity)
                continue
            }

            let isInsideGit = git(repoURL, ["rev-parse", "--is-inside-work-tree"])
            if isInsideGit.text.trimmingCharacters(in: .whitespacesAndNewlines) != "true" {
                activity.error = LocalizedText("Kein Git-Repository unter: \(repo.path)", "Not a Git repository: \(repo.path)")
                repoResults.append(activity)
                continue
            }

            // 1. Own commits
            activity.commits = git(repoURL, ["log", "--all", "--since-as-filter=\(start)", "--until=\(end)", authorArg, "-n", "150", "--format=%h | Autorzeit: %aI | Commitzeit: %cI | %s"])
            // 2. Changed files / diff stats
            activity.changedFiles = git(repoURL, ["log", "--all", "--since-as-filter=\(start)", "--until=\(end)", authorArg, "--shortstat", "--oneline", "-n", "30"])
            // 3. Local branch/HEAD activity
            activity.headActivity = git(repoURL, ["reflog", "show", "HEAD", "--since=\(start)", "--until=\(end)", "-n", "200", "--date=iso-strict", "--format=%gD | %gs"])
            // 4. Uncommitted working-tree changes (today only)
            if isToday {
                activity.workingTree = git(repoURL, ["status", "--short"])
            }

            repoResults.append(activity)
        }

        return GitActivityResult(date: day, timezone: AppTime.timeZone.identifier, repositories: repoResults)
    }

    static func formatLogText(_ result: GitActivityResult) -> String {
        var parts: [String] = [GitActivityResult.scope]
        func appendGitSection(_ title: String, _ output: GitOutput) {
            parts.append(title)
            if let err = output.error { parts.append(err.de) }
            else if !output.isEmpty { parts.append(output.text) }
            else { parts.append("(keine gefunden)") }
            if output.truncated { parts.append("(Ausgabe gekürzt)") }
        }
        func appendIfPresent(_ title: String, _ output: GitOutput) {
            guard !output.isEmpty else { return }
            parts.append(title)
            parts.append(output.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        for repo in result.repositories {
            parts.append("\nREPOSITORY: \(repo.title)")

            if let err = repo.error {
                parts.append("Status: \(err.de)")
                continue
            }

            appendGitSection("Eigene Commits:", repo.commits)
            appendIfPresent("Geänderte Dateien / Diff:", repo.changedFiles)
            appendIfPresent("Uncommittete Arbeitskopie (Heute):", repo.workingTree)
            appendGitSection("Lokale HEAD-Aktivitäten:", repo.headActivity)
        }
        return parts.joined(separator: "\n")
    }
}

/// One Git command's output for a repository.
struct GitOutput: Equatable {
    var text: String = ""
    var truncated: Bool = false
    var error: LocalizedText? = nil

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Non-blank output lines.
    var lines: [String] {
        text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// What a day's Git activity looks like for one tracked repository.
struct RepoActivity: Equatable {
    var folderName: String
    var projectName: String = ""
    var defaultTicket: String = ""
    var path: String = ""
    /// Set when the repository could not be read at all; the outputs below are then empty.
    var error: LocalizedText? = nil
    var commits = GitOutput()
    var changedFiles = GitOutput()
    var headActivity = GitOutput()
    var workingTree = GitOutput()

    init(folderName: String, projectName: String = "", defaultTicket: String = "", commits: GitOutput = GitOutput(),
         headActivity: GitOutput = GitOutput(), workingTree: GitOutput = GitOutput()) {
        self.folderName = folderName
        self.projectName = projectName
        self.defaultTicket = defaultTicket
        self.commits = commits
        self.headActivity = headActivity
        self.workingTree = workingTree
    }

    init(repo: TrackedRepo) {
        self.init(folderName: repo.folderName, projectName: repo.projectName, defaultTicket: repo.defaultTicket)
        path = repo.path
    }

    private var cleanProjectName: String { projectName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The project name, or the folder name without one.
    var displayLabel: String { cleanProjectName.isEmpty ? folderName : cleanProjectName }
    /// "Project (folder)", or just the folder name.
    var title: String { cleanProjectName.isEmpty ? folderName : "\(cleanProjectName) (\(folderName))" }
}

/// A day's Git activity across all enabled tracked repositories.
struct GitActivityResult: Equatable {
    static let scope = "Direkt aus der Desktop-App gelesen, ohne Server. Lokale Git-Referenzen; kein Fetch. Eigene Commits, Diff-Statistik, Reflogs und Working-Tree je Tracked-Repository."

    var date: String
    var timezone: String
    var repositories: [RepoActivity]
}
