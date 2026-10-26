import Foundation

// MARK: - AutoSynthesizer (Automatic Git & Notes Scanner)

enum AutoSynthesizer {
    static let ticketRegex = try! NSRegularExpression(pattern: #"\b([A-Z][A-Z0-9]+-\d+)\b"#, options: [])
    static let checkInRegex = try! NSRegularExpression(pattern: #"^-\s*\d{1,2}:\d{2}\s*\((\d+)\s*Min(?:\.|\b)\):\s*(?:\[([A-Z][A-Z0-9]+-\d+)\])?\s*(.*)$"#, options: [])
    static let durationRegex = try! NSRegularExpression(pattern: #"\b(\d{1,2}:[0-5]\d|\d+([.,]\d+)?\s*(?:h|std|stunden)|\d+\s*(?:m|min|minuten))\b"#, options: .caseInsensitive)

    static func extractTicket(from text: String) -> String? {
        let ns = text as NSString
        let matches = ticketRegex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let val = ns.substring(with: m.range(at: 1)).uppercased()
            if val != "PROJ-0" {
                return val
            }
        }
        return nil
    }

    static func cleanCommitSubject(_ subject: String) -> String {
        var s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<3 {
            // Remove conventional commit prefix like feat:, fix(scope):, etc.
            s = s.replacingOccurrences(of: #"^(feat|fix|docs|style|refactor|test|chore|perf|build|ci)(\([^)]*\))?:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            // Remove ticket prefix like PROJ-1234: or [PROJ-1234] or PROJ-1234
            s = s.replacingOccurrences(of: #"^\[?[A-Z][A-Z0-9]+-\d+\]?[:\s-]*"#, with: "", options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func synthesizeDay(day: String, journal: JournalItem, gitResult: [String: Any], existingEntries: [Entry]) -> [ProposedEntry] {
        var proposals: [ProposedEntry] = []

        // --- 1. Parse Notes (Check-ins & Freeform Notes) ---
        let noteLines = journal.notes.components(separatedBy: .newlines)
        var checkInAccumulator: [String: (ticket: String, desc: String, minutes: Int)] = [:]
        var checkInOrder: [String] = []

        for line in noteLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let ns = trimmed as NSString
            let checkInMatches = checkInRegex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length))

            if let m = checkInMatches.first {
                let lineMins = m.range(at: 1).location != NSNotFound ? (Int(ns.substring(with: m.range(at: 1))) ?? 30) : 30
                var ticket = ""
                if m.range(at: 2).location != NSNotFound {
                    let rawTicket = ns.substring(with: m.range(at: 2)).uppercased()
                    if rawTicket != "PROJ-0" { ticket = rawTicket }
                }
                let rawDesc = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                guard !rawDesc.isEmpty else { continue }

                let key = "\(ticket)||\(rawDesc.lowercased())"
                if let cur = checkInAccumulator[key] {
                    checkInAccumulator[key] = (ticket: cur.ticket, desc: cur.desc, minutes: cur.minutes + lineMins)
                } else {
                    checkInAccumulator[key] = (ticket: ticket, desc: rawDesc, minutes: lineMins)
                    checkInOrder.append(key)
                }
            } else {
                // Freeform line: check for duration pattern
                let durationMatches = durationRegex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length))
                if let dm = durationMatches.first {
                    let durStr = ns.substring(with: dm.range(at: 1))
                    if let parsedMinutes = try? SchichtaCore.parseMinutes(durStr) {
                        let ticket = extractTicket(from: trimmed) ?? ""
                        // Strip duration and ticket from the line to extract the task description
                        var cleanedDesc = trimmed
                        cleanedDesc = cleanedDesc.replacingOccurrences(of: durStr, with: "")
                        if !ticket.isEmpty {
                            cleanedDesc = cleanedDesc.replacingOccurrences(of: ticket, with: "")
                        }
                        // Clean leading bullets, brackets, dashes
                        cleanedDesc = cleanedDesc.replacingOccurrences(of: #"^[-*•\s\[\]:]+"#, with: "", options: .regularExpression)
                        cleanedDesc = cleanedDesc.replacingOccurrences(of: #"[-*•\s\[\]:]+$"#, with: "", options: .regularExpression)
                        cleanedDesc = cleanedDesc.trimmingCharacters(in: .whitespacesAndNewlines)

                        if cleanedDesc.count >= 3 {
                            let prop = ProposedEntry(
                                id: "note:\(day):\(proposals.count):\(cleanedDesc.hashValue)",
                                ticket: ticket,
                                description: cleanedDesc,
                                minutes: parsedMinutes,
                                estimated: true,
                                source: "Aus Tagesnotiz"
                            )
                            proposals.append(prop)
                        }
                    }
                }
            }
        }

        // Add accumulated 30m check-in proposals
        for key in checkInOrder {
            guard let item = checkInAccumulator[key] else { continue }
            let prop = ProposedEntry(
                id: "checkin:\(day):\(key)",
                ticket: item.ticket,
                description: item.desc,
                minutes: item.minutes,
                estimated: true,
                source: "Aus 30m Check-ins"
            )
            proposals.append(prop)
        }

        // --- 2. Parse Git Commits & Reflogs & Working Tree ---
        if let repos = gitResult["repositories"] as? [[String: Any]] {
            for repo in repos {
                let folderName = repo["repository"] as? String ?? "git"
                let projectName = (repo["projectName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let defaultTicket = (repo["defaultTicket"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let displayLabel = !projectName.isEmpty ? projectName : folderName

                let commitsDict = repo["commits"] as? [String: Any] ?? [:]
                let commitsText = commitsDict["text"] as? String ?? ""
                let commitLines = commitsText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                var repoHadCommits = false

                if !commitLines.isEmpty {
                    var ticketGroups: [String: [String]] = [:]
                    var order: [String] = []

                    for line in commitLines {
                        let parts = line.components(separatedBy: " | ")
                        guard parts.count >= 4 else { continue }
                        let subject = parts[3...].joined(separator: " | ")
                        var ticket = extractTicket(from: subject) ?? ""
                        if ticket.isEmpty && !defaultTicket.isEmpty {
                            ticket = defaultTicket
                        }
                        let cleanSubj = cleanCommitSubject(subject)
                        guard !cleanSubj.isEmpty else { continue }

                        if ticketGroups[ticket] == nil {
                            ticketGroups[ticket] = []
                            order.append(ticket)
                        }
                        if !ticketGroups[ticket]!.contains(cleanSubj) {
                            ticketGroups[ticket]!.append(cleanSubj)
                        }
                    }

                    for t in order {
                        guard let subjects = ticketGroups[t], !subjects.isEmpty else { continue }
                        let combinedSubjects = subjects.joined(separator: ", ")
                        let finalDesc = "\(displayLabel): \(combinedSubjects)"
                        // Estimate duration: 30m per distinct commit topic, max 120m
                        let estMinutes = min(120, max(30, subjects.count * 30))

                        let prop = ProposedEntry(
                            id: "git:\(folderName):\(day):\(t):\(finalDesc.hashValue)",
                            ticket: t,
                            description: finalDesc,
                            minutes: estMinutes,
                            estimated: true,
                            source: "Git · \(displayLabel)",
                            project: displayLabel
                        )
                        proposals.append(prop)
                        repoHadCommits = true
                    }
                }

                // If no commits found for this repo on this day, check working tree changes!
                if !repoHadCommits {
                    let wtDict = repo["working_tree"] as? [String: Any] ?? [:]
                    if let wtText = wtDict["text"] as? String {
                        let wtLines = wtText.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        if !wtLines.isEmpty {
                            let fileCount = wtLines.count
                            var branchTicket = ""
                            let headDict = repo["head_activity"] as? [String: Any] ?? [:]
                            if let headText = headDict["text"] as? String {
                                branchTicket = extractTicket(from: headText) ?? ""
                            }
                            let effectiveTicket = !branchTicket.isEmpty ? branchTicket : defaultTicket
                            let finalDesc = "\(displayLabel): Lokale Änderungen (\(fileCount) Dateien in Arbeit)"
                            let prop = ProposedEntry(
                                id: "git-wt:\(folderName):\(day):\(finalDesc.hashValue)",
                                ticket: effectiveTicket,
                                description: finalDesc,
                                minutes: 30,
                                estimated: true,
                                source: "Git · \(displayLabel) (Lokale Änderungen)",
                                project: displayLabel
                            )
                            proposals.append(prop)
                        }
                    }
                }
            }
        }

        // --- 3. Filter out items already recorded in existingEntries ---
        let filtered = proposals.filter { prop in
            let pDesc = prop.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let pTicket = prop.ticket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            for e in existingEntries {
                let eDesc = e.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let eTicket = e.ticket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

                if pTicket.isEmpty {
                    if eDesc == pDesc || eDesc.contains(pDesc) || pDesc.contains(eDesc) {
                        return false
                    }
                } else {
                    if eTicket == pTicket && (eDesc == pDesc || eDesc.contains(pDesc) || pDesc.contains(eDesc)) {
                        return false
                    }
                }
            }
            return true
        }

        // Deduplicate proposals with exact same ticket and description
        var unique: [ProposedEntry] = []
        var seen = Set<String>()
        for p in filtered {
            let key = "\(p.ticket.uppercased())||\(p.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(p)
            }
        }

        return unique
    }
}
