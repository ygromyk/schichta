import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Tab 1: General & Data

    var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label(store.t("settings.language"), systemImage: "globe")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(store.t("settings.appLanguage"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $store.appLanguage) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    Text(store.t("settings.switchesTheEntireUiMenus"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            GroupBox(label: Label(store.t("settings.timeZone"), systemImage: "globe.europe.africa")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(store.t("settings.daysAndTimesIn"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $store.timeZoneIdentifier) {
                            Text(store.t("settings.system", "\(TimeZone.current.identifier)")).tag("")
                            Divider()
                            ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { id in
                                Text(id).tag(id)
                            }
                        }
                        .frame(width: 260)
                    }
                    Text(store.t("settings.decidesWhenADayStarts"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            GroupBox(label: Label(store.t("settings.checkInBehavior"), systemImage: "clock")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(store.t("settings.defaultMode"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $store.defaultCheckInMode) {
                            ForEach(CheckInMode.allCases) { m in
                                Text(m.title(for: store.appLanguage)).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                    Text(store.t("settings.definesWhetherCheckInsCreate"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Divider()

                    Toggle(store.t("settings.openTheCheckInFrom", "\(GlobalHotKey.displayName)"), isOn: $store.globalHotKeyEnabled)
                        .font(.system(size: 12))

                    Toggle(store.t("settings.showInDockOffMenu"), isOn: $store.showInDock)
                        .font(.system(size: 12))

                    Toggle(store.t("settings.startAtLogin"), isOn: Binding(
                        get: { LoginItem.isEnabled },
                        set: { enabled in
                            do {
                                try LoginItem.setEnabled(enabled)
                            } catch {
                                store.showToast(store.t("settings.loginItemNotChanged", "\(error.localizedDescription)"))
                            }
                            store.objectWillChange.send()
                        }
                    ))
                    .font(.system(size: 12))
                    if LoginItem.status == .requiresApproval {
                        Text(store.t("settings.pleaseAllowItInSystem"))
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
                .padding(10)
            }

            GroupBox(label: Label(store.t("settings.userReports"), systemImage: "person.crop.circle")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("settings.nameForDraftGitAuthor"))
                        .font(.system(size: 12, weight: .medium))
                    TextField("Max Mustermann", text: $store.gitAuthorFilter)
                        .textFieldStyle(.roundedBorder)
                    Text(store.t("settings.usedAsFilterForGit"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            GroupBox(label: Label(store.t("settings.dataBackup"), systemImage: "internaldrive")) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.t("settings.databaseLocation"))
                            .font(.system(size: 12, weight: .medium))
                        Text(store.storeURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 10) {
                        Button(store.t("settings.showInFinder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([store.storeURL])
                        }

                        Spacer()

                        Button(store.t("settings.exportBackup")) {
                            store.exportBackup(window: nil)
                        }

                        Button(store.t("settings.importBackup")) {
                            store.importBackup(window: nil)
                        }
                    }
                }
                .padding(10)
            }
        }
    }
}
