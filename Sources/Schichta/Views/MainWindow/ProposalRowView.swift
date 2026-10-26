import AppKit
import SwiftUI

// MARK: - Proposal Row View

struct ProposalRowView: View {
    @State var proposal: ProposedEntry
    var onAccept: (ProposedEntry) -> Void
    var language: AppLanguage = .de

    @State private var timeStr: String = ""

    private func t(_ de: String, _ en: String) -> String {
        language == .de ? de : en
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Source badge
                Text(proposal.source)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(SchichtaTheme.forestGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SchichtaTheme.forestGreen.opacity(0.12))
                    .cornerRadius(4)

                if !proposal.project.isEmpty {
                    Text(proposal.project)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)
                }

                Spacer()

                Button(t("＋ Übernehmen", "＋ Accept")) {
                    if let mins = try? SchichtaCore.parseMinutes(timeStr) {
                        proposal.minutes = mins
                    }
                    onAccept(proposal)
                }
                .buttonStyle(.borderedProminent)
                .tint(SchichtaTheme.forestGreen)
                .controlSize(.small)
            }

            HStack(spacing: 6) {
                TextField(t("Ticket", "Ticket"), text: $proposal.ticket)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)

                StepButton(increase: false, size: 15, help: t("−15 Minuten (mind. 5 Min.)", "−15 minutes (min. 5 min.)")) {
                    let cur = (try? SchichtaCore.parseMinutes(timeStr)) ?? proposal.minutes
                    let next = SchichtaCore.clampDuration(cur - 15)
                    timeStr = SchichtaCore.formatTime(next)
                    proposal.minutes = next
                }

                TextField("0:15", text: $timeStr)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 58)

                StepButton(increase: true, size: 15, help: t("+15 Minuten", "+15 minutes")) {
                    let cur = (try? SchichtaCore.parseMinutes(timeStr)) ?? proposal.minutes
                    let next = SchichtaCore.clampDuration(cur + 15)
                    timeStr = SchichtaCore.formatTime(next)
                    proposal.minutes = next
                }

                TextField(t("Tätigkeit", "Activity"), text: $proposal.description)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .onAppear {
            self.timeStr = SchichtaCore.formatTime(proposal.minutes)
        }
    }
}
