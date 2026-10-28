import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Tab 4: Integrations & Hooks

    var integrationsAndHooksTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section 1: overview & documentation
            GroupBox(label: Label(store.t("settings.externalIntegrationsWebhooks"), systemImage: "network")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.t("settings.seamlesslyIntegrateSchichtaWithExternal"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("settings.environmentVariablesForShellHooks"))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.secondary)

                        Text("• SCHICHTA_DATE: Ausgewählter Tag (YYYY-MM-DD)\n• SCHICHTA_TOTAL_MINUTES: Summe der Minuten (z. B. 90)\n• SCHICHTA_TOTAL_HHMM: Formatierte Gesamtdauer (z. B. 01:30)\n• SCHICHTA_JSON_FILE: Pfad zur JSON-Datei (~/Library/Application Support/Schichta/last-export.json)\n• SCHICHTA_REPORT: Vollständiger formatierter Tagesentwurf\n• stdin: Vollständiges JSON-Payload mit allen Repos & Einträgen")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }

                    HStack {
                        Button(action: { store.copySampleHookPayload() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "doc.on.doc")
                                Text(store.t("settings.copySampleJson"))
                            }
                        }
                        .controlSize(.small)

                        Spacer()
                    }
                }
                .padding(10)
            }

            BookingTargetsSection(store: store)

            AISettingsSection(store: store)

            // Section 2: configuration
            GroupBox(label: Label(store.t("settings.hookConfiguration"), systemImage: "wrench.and.screwdriver")) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("settings.localShellCommandCliScript"))
                            .font(.system(size: 11.5, weight: .medium))
                        TextField("/usr/local/bin/book-time oder python3 ~/scripts/book_time.py", text: $store.hookShellCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                        Text(store.t("settings.executedViaBinZshC"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("settings.httpPostWebhookUrl"))
                            .font(.system(size: 11.5, weight: .medium))
                        TextField("http://127.0.0.1:8765/webhook", text: $store.hookWebhookURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                        Text(store.t("settings.sendsAnHttpPostRequest"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    Toggle(store.t("settings.runHookAutomaticallyWhenA"), isOn: $store.hookAutoTriggerOnBook)
                        .font(.system(size: 11.5))
                }
                .padding(10)
            }

            // Section 3: test hook & status
            GroupBox(label: Label(store.t("settings.testHookLiveStatus"), systemImage: "bolt.fill")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(action: { store.runExternalHook(for: store.selectedDay) }) {
                            HStack(spacing: 5) {
                                Image(systemName: "bolt.fill")
                                Text(store.t("settings.testHookNowWithDay", "\(SchichtaCore.formatGermanDate(store.selectedDay))"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SchichtaTheme.forestGreen)
                        .controlSize(.regular)

                        Spacer()
                    }

                    if !store.lastHookResult.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.t("settings.lastHookOutput"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.secondary)

                            Text(store.lastHookResult)
                                .font(.system(size: 10.5, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(10)
            }
        }
    }
}
