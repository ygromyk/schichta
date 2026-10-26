import AppKit

extension SchichtaStore {
    func copySampleHookPayload() {
        let day = selectedDay
        let entries = entriesForSelectedDay().isEmpty ? [
            Entry(id: "sample-1", date: day, ticket: "PROJ-2800", description: "Example App: Replay prüfen", minutes: 90, estimated: false, project: "Example App")
        ] : entriesForSelectedDay()
        let payload = SchichtaCore.buildHookPayload(day: day, entries: entries, repos: trackedRepos, author: gitAuthorFilter)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let jsonStr = String(data: data, encoding: .utf8) {
            copyToPasteboard(jsonStr)
            showToast(t("Beispiel-JSON in Zwischenablage kopiert.", "Sample JSON copied to clipboard."))
        }
    }

    /// Liest die Git-Aktivität eines Tages im Hintergrund, speichert sie als Tageslog und meldet das Ergebnis auf dem Main-Thread.
    func loadGitActivity(for day: String, completion: @escaping (Result<(result: [String: Any], journal: JournalItem), Error>) -> Void) {
        let repos = trackedRepos
        let author = gitAuthorFilter
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let read = Result { try Activity.readRepos(day, repos: repos, authorFilter: author) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                completion(read.map { gitResult in
                    var journal = self.database.journal[day] ?? JournalItem()
                    journal.logs = Activity.formatLogText(gitResult)
                    self.database.journal[day] = journal
                    self.save()
                    self.inspectedGitResult = gitResult
                    return (gitResult, journal)
                })
            }
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
                self.showToast(self.t("Fehler bei Git-Prüfung: \(error.localizedDescription)", "Git inspection error: \(error.localizedDescription)"))
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
            jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results: [String] = []
            var allSuccess = true

            // 1. Shell Hook
            if !shellCmd.isEmpty {
                var env = ProcessInfo.processInfo.environment
                env["SCHICHTA_DATE"] = day
                let totalMins = entries.reduce(0) { $0 + $1.minutes }
                env["SCHICHTA_TOTAL_MINUTES"] = "\(totalMins)"
                env["SCHICHTA_TOTAL_HHMM"] = SchichtaCore.formatTime(totalMins)
                env["SCHICHTA_JSON_FILE"] = exportURL.path
                env["SCHICHTA_REPORT"] = SchichtaCore.bcsReport(day: day, entries: entries)
                env["SCHICHTA_BCS_REPORT"] = env["SCHICHTA_REPORT"] // alter Name, für bestehende Skripte

                do {
                    // Großzügiges Zeitlimit: Adapter wie schichta-bcs starten einen Browser und loggen sich ein.
                    let run = try Shell.run("/bin/zsh", ["-c", shellCmd], stdin: jsonData, environment: env, mergeStderr: true, timeout: 180)
                    let output = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if run.status == 0 {
                        let snippet = output.isEmpty ? "OK" : String(output.prefix(2000))
                        results.append("Shell-Hook (Exit 0): \(snippet)")
                    } else {
                        allSuccess = false
                        results.append("Shell-Hook Fehler (Exit \(run.status)): \(output)")
                    }
                } catch {
                    allSuccess = false
                    results.append("Shell-Hook Startfehler: \(error.localizedDescription)")
                }
            }

            // 2. HTTP Webhook
            if !webhookURLStr.isEmpty {
                if let url = URL(string: webhookURLStr) {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Schichta-Desktop/1.0", forHTTPHeaderField: "User-Agent")
                    request.httpBody = jsonData
                    request.timeoutInterval = 15

                    let sema = DispatchSemaphore(value: 0)
                    let task = URLSession.shared.dataTask(with: request) { data, response, err in
                        if let err = err {
                            allSuccess = false
                            results.append("Webhook Fehler: \(err.localizedDescription)")
                        } else if let http = response as? HTTPURLResponse {
                            if (200...299).contains(http.statusCode) {
                                results.append("Webhook HTTP \(http.statusCode): OK")
                            } else {
                                allSuccess = false
                                let snippet = data != nil ? String(decoding: data!, as: UTF8.self).prefix(150) : ""
                                results.append("Webhook HTTP \(http.statusCode): \(snippet)")
                            }
                        }
                        sema.signal()
                    }
                    task.resume()
                    _ = sema.wait(timeout: .now() + 16)
                } else {
                    allSuccess = false
                    results.append("Webhook-URL ungültig: \(webhookURLStr)")
                }
            }

            let summary = results.joined(separator: " · ")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.lastHookResult = summary
                self.showToast(allSuccess ? self.t("Hook erfolgreich: \(summary)", "Hook success: \(summary)") : self.t("Hook-Meldung: \(summary)", "Hook message: \(summary)"))
                completion?(allSuccess, summary)
            }
        }
    }
}
