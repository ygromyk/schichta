import AppKit

extension SchichtaStore {
    /// Adds a repo unless its path is already tracked. Without a project name: the folder name, "my-app" → "My App".
    @discardableResult
    func addTrackedRepo(path: String, projectName: String = "", defaultTicket: String = "") -> Bool {
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPath.isEmpty, !trackedRepos.contains(where: { $0.path == cleanPath }) else { return false }
        let pName = !projectName.isEmpty ? projectName : URL(fileURLWithPath: cleanPath).lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
        trackedRepos.append(TrackedRepo(path: cleanPath, projectName: pName, defaultTicket: defaultTicket, enabled: true))
        return true
    }

    func removeTrackedRepo(id: String) {
        trackedRepos.removeAll(where: { $0.id == id })
    }

    /// Adds every direct subfolder of `rootPath` that is a Git repository.
    func scanAndAddRepos(in rootPath: String) -> Int {
        let rootURL = URL(fileURLWithPath: rootPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            showToast(t("Verzeichnis konnte nicht gelesen werden: \(rootPath)", "Could not read directory: \(rootPath)"))
            return 0
        }
        var added = 0
        for item in contents {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue,
                  FileManager.default.fileExists(atPath: item.appendingPathComponent(".git").path) else { continue }
            if addTrackedRepo(path: item.path) { added += 1 }
        }
        if added > 0 {
            showToast(t("\(added) neue(s) Git-Repository(s) hinzugefügt.", "\(added) new Git repository(s) added."))
        } else {
            showToast(t("Keine neuen Repositories in \(rootPath) gefunden.", "No new repositories found in \(rootPath)."))
        }
        return added
    }
}
