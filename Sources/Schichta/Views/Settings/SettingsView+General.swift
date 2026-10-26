import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Tab 1: Allgemein & Daten

    var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label(store.t("Sprache / Language", "Language"), systemImage: "globe")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(store.t("App-Sprache:", "App Language:"))
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
                    Text(store.t("Schaltet die gesamte Oberfläche, Menüs, Prompts und Datumsformate live um.", "Switches the entire UI, menus, prompts, and date formats live."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            GroupBox(label: Label(store.t("Zeitzone", "Time Zone"), systemImage: "globe.europe.africa")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(store.t("Tage und Uhrzeiten in:", "Days and times in:"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $store.timeZoneIdentifier) {
                            Text(store.t("System (\(TimeZone.current.identifier))", "System (\(TimeZone.current.identifier))")).tag("")
                            Divider()
                            ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { id in
                                Text(id).tag(id)
                            }
                        }
                        .frame(width: 260)
                    }
                    Text(store.t("Bestimmt, wann ein Tag beginnt und endet (Git-Abfragen, Check-ins, Erinnerungen) und in welcher Zeit Uhrzeiten angezeigt werden.", "Decides when a day starts and ends (Git queries, check-ins, reminders) and in which zone times are shown."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            GroupBox(label: Label(store.t("Check-in Verhalten", "Check-in Behavior"), systemImage: "clock")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(store.t("Standard-Modus:", "Default mode:"))
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
                    Text(store.t("Legt fest, ob ein Check-in sofort eine buchungswirksame Tätigkeit erzeugt oder nur die Tagesnotiz ergänzt.", "Defines whether check-ins create a billable activity immediately or only append to the day note."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            GroupBox(label: Label(store.t("Benutzer & Berichte", "User & Reports"), systemImage: "person.crop.circle")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("Name für Entwurf & Git-Autor:", "Name for draft & Git author:"))
                        .font(.system(size: 12, weight: .medium))
                    TextField("Max Mustermann", text: $store.gitAuthorFilter)
                        .textFieldStyle(.roundedBorder)
                    Text(store.t("Wird als Filter für 'git log --author' und in der Kopfzeile des Tagesentwurfs verwendet.", "Used as filter for 'git log --author' and in the header of the daily draft."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            GroupBox(label: Label(store.t("Daten & Sicherung", "Data & Backup"), systemImage: "internaldrive")) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.t("Datenbank-Speicherort:", "Database location:"))
                            .font(.system(size: 12, weight: .medium))
                        Text(store.storeURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 10) {
                        Button(store.t("Im Finder anzeigen", "Show in Finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([store.storeURL])
                        }

                        Spacer()

                        Button(store.t("Sicherung exportieren…", "Export backup…")) {
                            store.exportBackup(window: nil)
                        }

                        Button(store.t("Sicherung importieren…", "Import backup…")) {
                            store.importBackup(window: nil)
                        }
                    }
                }
                .padding(10)
            }
        }
    }
}
