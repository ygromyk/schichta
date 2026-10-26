import AppKit

extension SchichtaStore {
    func copySampleHookPayload() {
        let day = selectedDay
        let entries = entriesForSelectedDay().isEmpty ? [
            Entry(id: "sample-1", date: day, ticket: "PROJ-2800", description: "Example App: Replay prüfen", minutes: 90, estimated: false, project: "Example App")
        ] : entriesForSelectedDay()
        let payload = SchichtaCore.buildHookPayload(day: day, entries: entries, repos: trackedRepos, author: gitAuthorFilter)
        if let data = try? payload.json(),
           let jsonStr = String(data: data, encoding: .utf8) {
            copyToPasteboard(jsonStr)
            showToast(t("Beispiel-JSON in Zwischenablage kopiert.", "Sample JSON copied to clipboard."))
        }
    }

    /// Reads a day's Git activity in the background, saves it as the day's log and reports back on the main actor.
    func loadGitActivity(for day: String, completion: @escaping (Result<(result: GitActivityResult, journal: JournalItem), Error>) -> Void) {
        let repos = trackedRepos
        let author = gitAuthorFilter
        Task {
            let read = await Task.detached(priority: .userInitiated) {
                Result { try Activity.readRepos(day, repos: repos, authorFilter: author) }
            }.value
            completion(read.map { gitResult in
                var journal = database.journal[day] ?? JournalItem()
                journal.logs = Activity.formatLogText(gitResult)
                database.journal[day] = journal
                save()
                inspectedGitResult = gitResult
                return (gitResult, journal)
            })
        }
    }

    func inspectGitActivityForSelectedDay() {
        isInspectingGit = true
        let day = selectedDay
        loadGitActivity(for: day) { [weak self] outcome in
            guard let self = self else { return }
            self.isInspectingGit = false
            switch outcome {
            case .success:
                self.showToast(self.t("Git-Aktivitäten für \(SchichtaCore.formatGermanDate(day)) geprüft.", "Git activities inspected for \(SchichtaCore.formatGermanDate(day))."))
            case .failure(let error):
                self.showToast(self.t("Fehler bei Git-Prüfung: \(self.describe(error))", "Git inspection error: \(self.describe(error))"))
            }
        }
    }

    func runExternalHook(for day: String, completion: ((Bool, String) -> Void)? = nil) {
        let entries = database.entries.filter { $0.date == day }
        let shellCmd = self.hookShellCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let webhookURLStr = self.hookWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = SchichtaCore.buildHookPayload(day: day, entries: entries, repos: trackedRepos, author: gitAuthorFilter)
        let exportURL = AppPaths.support.appendingPathComponent("last-export.json")

        let jsonData: Data
        do {
            jsonData = try payload.json()
            try jsonData.write(to: exportURL, options: .atomic)
        } catch {
            let errStr = t("Fehler beim Erzeugen des JSON: \(error.localizedDescription)", "Error creating JSON: \(error.localizedDescription)")
            self.lastHookResult = errStr
            self.showToast(errStr)
            completion?(false, errStr)
            return
        }

        if shellCmd.isEmpty && webhookURLStr.isEmpty {
            let msg = t("JSON exportiert nach: \(exportURL.lastPathComponent)", "JSON exported to: \(exportURL.lastPathComponent)")
            self.lastHookResult = msg
            self.showToast(msg)
            completion?(true, msg)
            return
        }

        showToast(t("Führe externen Hook aus...", "Running external hook..."))
        let language = appLanguage

        Task {
            var results: [String] = []
            var allSuccess = true

            // 1. Shell Hook (blocking, so on a background thread)
            if !shellCmd.isEmpty {
                let shell = await Task.detached(priority: .userInitiated) {
                    Self.runShellHook(shellCmd, day: day, entries: entries, jsonData: jsonData, exportURL: exportURL, language: language)
                }.value
                allSuccess = allSuccess && shell.ok
                results.append(shell.message)
            }

            // 2. HTTP Webhook
            if !webhookURLStr.isEmpty {
                let webhook = await Self.postWebhook(webhookURLStr, jsonData: jsonData, language: language)
                allSuccess = allSuccess && webhook.ok
                results.append(webhook.message)
            }

            let summary = results.joined(separator: " · ")
            lastHookResult = summary
            showToast(allSuccess ? t("Hook erfolgreich: \(summary)", "Hook success: \(summary)") : t("Hook-Meldung: \(summary)", "Hook message: \(summary)"))
            completion?(allSuccess, summary)
        }
    }

    nonisolated private static func runShellHook(_ command: String, day: String, entries: [Entry], jsonData: Data, exportURL: URL,
                                                 language: AppLanguage) -> (ok: Bool, message: String) {
        func say(_ de: String, _ en: String) -> String { LocalizedText(de, en).in(language) }
        var env = ProcessInfo.processInfo.environment
        env["SCHICHTA_DATE"] = day
        let totalMins = entries.reduce(0) { $0 + $1.minutes }
        env["SCHICHTA_TOTAL_MINUTES"] = "\(totalMins)"
        env["SCHICHTA_TOTAL_HHMM"] = SchichtaCore.formatTime(totalMins)
        env["SCHICHTA_JSON_FILE"] = exportURL.path
        env["SCHICHTA_REPORT"] = SchichtaCore.bcsReport(day: day, entries: entries)
        env["SCHICHTA_BCS_REPORT"] = env["SCHICHTA_REPORT"] // old name, kept for existing scripts

        do {
            // Generous timeout: adapters like schichta-bcs start a browser and log in.
            let run = try Shell.run("/bin/zsh", ["-c", command], stdin: jsonData, environment: env, mergeStderr: true, timeout: 180)
            let output = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if run.status == 0 {
                let snippet = output.isEmpty ? "OK" : String(output.prefix(2000))
                return (true, say("Shell-Hook (Exit 0): \(snippet)", "Shell hook (exit 0): \(snippet)"))
            }
            return (false, say("Shell-Hook Fehler (Exit \(run.status)): \(output)", "Shell hook error (exit \(run.status)): \(output)"))
        } catch {
            return (false, say("Shell-Hook Startfehler: \(error.localizedDescription)", "Shell hook failed to start: \(error.localizedDescription)"))
        }
    }

    nonisolated private static func postWebhook(_ urlString: String, jsonData: Data, language: AppLanguage) async -> (ok: Bool, message: String) {
        func say(_ de: String, _ en: String) -> String { LocalizedText(de, en).in(language) }
        guard let url = URL(string: urlString) else {
            return (false, say("Webhook-URL ungültig: \(urlString)", "Invalid webhook URL: \(urlString)"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Schichta-Desktop/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = jsonData
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                return (true, "Webhook HTTP \(status): OK")
            }
            return (false, "Webhook HTTP \(status): \(String(decoding: data, as: UTF8.self).prefix(150))")
        } catch {
            return (false, say("Webhook Fehler: \(error.localizedDescription)", "Webhook error: \(error.localizedDescription)"))
        }
    }
}
