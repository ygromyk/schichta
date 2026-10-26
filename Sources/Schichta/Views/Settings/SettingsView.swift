import AppKit
import SwiftUI

// MARK: - Settings View (macOS Preferences Window)

enum SettingsTab: String, CaseIterable {
    case general, workHours, gitRepos, integrations
}

struct SettingsView: View {
    @ObservedObject var store: SchichtaStore

    var body: some View {
        VStack(spacing: 0) {
            // macOS Style Tab Picker
            Picker("", selection: $store.settingsSelectedTab) {
                Label(store.t("Allgemein", "General"), systemImage: "gearshape").tag(SettingsTab.general)
                Label(store.t("Arbeitszeit & Prompts", "Work Hours & Prompts"), systemImage: "clock.badge.checkmark").tag(SettingsTab.workHours)
                Label(store.t("Git-Repos & Prüfung", "Git Repos & Inspector"), systemImage: "arrow.triangle.branch").tag(SettingsTab.gitRepos)
                Label(store.t("Integrationen & Hooks", "Integrations & Hooks"), systemImage: "network").tag(SettingsTab.integrations)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch store.settingsSelectedTab {
                    case .general:
                        generalTab
                    case .workHours:
                        workHoursAndPromptsTab
                    case .gitRepos:
                        gitReposAndInspectorTab
                    case .integrations:
                        integrationsAndHooksTab
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, idealWidth: 720, minHeight: 620, idealHeight: 620)
    }

    func chooseGitDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        startInProjectsRoot(panel)
        if panel.runModal() == .OK {
            panel.urls.forEach { store.addTrackedRepo(path: $0.path) }
        }
    }

    /// Lets the user pick a folder, remembers it, and adds every Git repository directly inside it.
    func chooseFolderToScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = store.t("Durchsuchen", "Scan")
        startInProjectsRoot(panel)
        if panel.runModal() == .OK, let url = panel.url {
            store.gitProjectsRoot = url.path
            _ = store.scanAndAddRepos(in: url.path)
        }
    }

    private func startInProjectsRoot(_ panel: NSOpenPanel) {
        let root = store.gitProjectsRoot
        if !root.isEmpty, FileManager.default.fileExists(atPath: root) {
            panel.directoryURL = URL(fileURLWithPath: root)
        }
    }

    func statPill(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.12))
        .cornerRadius(4)
    }
}
