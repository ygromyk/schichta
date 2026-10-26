import AppKit
import SwiftUI

// MARK: - Settings View (macOS Preferences Window)

struct SettingsView: View {
    @ObservedObject var store: SchichtaStore

    var body: some View {
        VStack(spacing: 0) {
            // macOS Style Tab Picker
            Picker("", selection: $store.settingsSelectedTab) {
                Label(store.t("Allgemein", "General"), systemImage: "gearshape").tag(0)
                Label(store.t("Arbeitszeit & Prompts", "Work Hours & Prompts"), systemImage: "clock.badge.checkmark").tag(1)
                Label(store.t("Git-Repos & Prüfung", "Git Repos & Inspector"), systemImage: "arrow.triangle.branch").tag(2)
                Label(store.t("Integrationen & Hooks", "Integrations & Hooks"), systemImage: "network").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch store.settingsSelectedTab {
                    case 0:
                        generalTab
                    case 1:
                        workHoursAndPromptsTab
                    case 2:
                        gitReposAndInspectorTab
                    case 3:
                        integrationsAndHooksTab
                    default:
                        generalTab
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
        let curUrl = URL(fileURLWithPath: store.gitProjectsRoot)
        if FileManager.default.fileExists(atPath: curUrl.path) {
            panel.directoryURL = curUrl
        }
        if panel.runModal() == .OK {
            panel.urls.forEach { store.addTrackedRepo(path: $0.path) }
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
