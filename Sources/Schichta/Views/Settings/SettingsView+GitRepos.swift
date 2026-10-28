import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Tab 3: Git Repos & Inspection

    var gitReposAndInspectorTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section 1: tracked repositories
            GroupBox(label: Label(store.t("settings.trackedGitRepositories"), systemImage: "arrow.triangle.branch")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.t("settings.addAnyLocalGitDirectories"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Button(action: { chooseGitDirectories() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                Text(store.t("settings.addGitDirectory"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SchichtaTheme.forestGreen)
                        .controlSize(.small)

                        Button(action: { chooseFolderToScan() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "folder.badge.gearshape")
                                Text(store.t("settings.findGitFoldersInA"))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()
                    }

                    if store.trackedRepos.isEmpty {
                        Text(store.t("settings.noRepositoriesTrackedYetClick"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 10)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(store.trackedRepos.enumerated()), id: \.element.id) { idx, repo in
                                let isGit = FileManager.default.fileExists(atPath: URL(fileURLWithPath: repo.path).appendingPathComponent(".git").path)

                                HStack(alignment: .top, spacing: 10) {
                                    Toggle("", isOn: $store.trackedRepos[idx].enabled)
                                        .labelsHidden()
                                        .padding(.top, 4)
                                        .help(store.t("settings.enableDisableRepositoryForGit"))

                                    Circle()
                                        .fill(isGit ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 9)
                                        .help(isGit ? store.t("settings.validGitRepoGitPresent") : store.t("settings.noGitFolderFound"))

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(repo.folderName)
                                                .font(.system(size: 13, weight: .bold))

                                            if !repo.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text("(\(repo.projectName))")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(SchichtaTheme.forestGreen)
                                            }

                                            Spacer()

                                            Button(action: {
                                                store.removeTrackedRepo(id: repo.id)
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red.opacity(0.8))
                                            }
                                            .buttonStyle(.plain)
                                            .help(store.t("settings.removeRepository"))
                                        }

                                        Text(repo.path)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(store.t("settings.projectNameForReportsHooks"))
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.secondary)
                                                TextField(store.t("settings.exampleExampleApp"), text: $store.trackedRepos[idx].projectName)
                                                    .textFieldStyle(.roundedBorder)
                                                    .font(.system(size: 11.5))
                                            }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(store.t("settings.defaultTicketOptional"))
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.secondary)
                                                TextField(store.t("settings.exampleProj2800"), text: $store.trackedRepos[idx].defaultTicket)
                                                    .textFieldStyle(.roundedBorder)
                                                    .font(.system(size: 11.5))
                                                    .frame(width: 170)
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                            }
                        }
                    }
                }
                .padding(10)
            }

            // Section 2: local day activity inspector
            GroupBox(label: Label(store.t("settings.localGitInspectionFor", "\(SchichtaCore.formatGermanDate(store.selectedDay))"), systemImage: "magnifyingglass")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.t("settings.inspectsAllActiveRepositoriesFor"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Button(action: { store.inspectGitActivityForSelectedDay() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "magnifyingglass")
                                Text(store.t("settings.inspectLocalDayActivityNow"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SchichtaTheme.forestGreen)
                        .controlSize(.regular)
                        .disabled(store.isInspectingGit)

                        Button(action: { store.synthesizeDayAction() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                Text(store.t("settings.applyAsProposals"))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(store.isSynthesizing || store.isInspectingGit)

                        Spacer()
                    }

                    if store.isInspectingGit {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(store.t("settings.readingLocalGitActivityFrom"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    // Stats per repo
                    if let repos = store.inspectedGitResult?.repositories, !repos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.t("settings.recognizedActivityByRepository"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            ForEach(Array(repos.enumerated()), id: \.offset) { _, r in
                                let commitCount = r.commits.lines.count
                                let hasDiff = !r.changedFiles.isEmpty
                                let reflogCount = r.headActivity.lines.count
                                let wtCount = r.workingTree.lines.count

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(r.title)
                                            .font(.system(size: 12, weight: .bold))
                                        Spacer()
                                        if let err = r.error {
                                            Text(err.in(store.appLanguage))
                                                .font(.system(size: 10))
                                                .foregroundColor(.red)
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        statPill(label: store.t("settings.commits", "\(commitCount)"), icon: "checkmark.circle", color: commitCount > 0 ? SchichtaTheme.forestGreen : .secondary)
                                        statPill(label: store.t(hasDiff ? "settings.diffFound" : "settings.noDiff"), icon: "doc.badge.gearshape", color: hasDiff ? .blue : .secondary)
                                        statPill(label: store.t("settings.headLogs", "\(reflogCount)"), icon: "arrow.triangle.branch", color: reflogCount > 0 ? .purple : .secondary)
                                        if store.selectedDay == SchichtaCore.day() {
                                            statPill(label: store.t("settings.uncommitted", "\(wtCount)"), icon: "pencil.circle", color: wtCount > 0 ? .orange : .secondary)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                            }
                        }
                    }

                    // Detailed log
                    let logs = store.journalForSelectedDay().logs
                    if !logs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.t("settings.detailedGitLog"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            ScrollView {
                                Text(logs)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .textSelection(.enabled)
                            }
                            .frame(height: 140)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                        }
                    }
                }
                .padding(10)
            }
        }
    }
}
