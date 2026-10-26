import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Tab 4: Integrationen & Hooks

    var integrationsAndHooksTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sektion 1: Übersicht & Dokumentation
            GroupBox(label: Label(store.t("Externe Integrationen & Webhooks", "External Integrations & Webhooks"), systemImage: "network")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.t("Integriere Schichta nahtlos mit deinen externen Tools (z. B. lokales Shell- oder Python-Skript, n8n, Zapier, Webhook oder eigener Adapter). Jedem Eintrag wird automatisch der zugehörige Projektname des Repos zugeordnet.", "Seamlessly integrate Schichta with external tools (e.g. local shell or Python scripts, n8n, Zapier, webhook, or your own adapter). Each entry is automatically mapped to its repository project name."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("Umgebungsvariablen für Shell-Hooks:", "Environment variables for Shell hooks:"))
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
                                Text(store.t("Beispiel-JSON kopieren", "Copy sample JSON"))
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

            // Sektion 2: Konfiguration
            GroupBox(label: Label(store.t("Hook-Konfiguration", "Hook Configuration"), systemImage: "wrench.and.screwdriver")) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("Lokaler Shell-Befehl / CLI-Skript:", "Local Shell Command / CLI script:"))
                            .font(.system(size: 11.5, weight: .medium))
                        TextField("/usr/local/bin/book-time oder python3 ~/scripts/book_time.py", text: $store.hookShellCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                        Text(store.t("Wird via '/bin/zsh -c' ausgeführt. Erhält das JSON über stdin und gesetzte Umgebungsvariablen.", "Executed via '/bin/zsh -c'. Receives JSON payload via stdin and environment variables."))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("HTTP POST Webhook URL:", "HTTP POST Webhook URL:"))
                            .font(.system(size: 11.5, weight: .medium))
                        TextField("http://127.0.0.1:8765/webhook", text: $store.hookWebhookURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                        Text(store.t("Sendet einen HTTP POST Request mit Content-Type: application/json an diesen Endpunkt.", "Sends an HTTP POST request with Content-Type: application/json to this endpoint."))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    Toggle(store.t("Hook automatisch ausführen, wenn ein Tag als gebucht abgeschlossen wird", "Run hook automatically when a day is marked as booked"), isOn: $store.hookAutoTriggerOnBook)
                        .font(.system(size: 11.5))
                }
                .padding(10)
            }

            // Sektion 3: Hook Testen & Status
            GroupBox(label: Label(store.t("Hook testen & Live-Status", "Test Hook & Live Status"), systemImage: "bolt.fill")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(action: { store.runExternalHook(for: store.selectedDay) }) {
                            HStack(spacing: 5) {
                                Image(systemName: "bolt.fill")
                                Text(store.t("Hook jetzt mit Tag \(SchichtaCore.formatGermanDate(store.selectedDay)) testen", "Test hook now with day \(SchichtaCore.formatGermanDate(store.selectedDay))"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SchichtaTheme.forestGreen)
                        .controlSize(.regular)

                        Spacer()
                    }

                    if !store.lastHookResult.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.t("Letzte Hook-Ausgabe:", "Last hook output:"))
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
