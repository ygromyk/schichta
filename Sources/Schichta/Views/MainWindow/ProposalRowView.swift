import AppKit
import SwiftUI

// MARK: - Proposal Row View

struct ProposalRowView: View {
    @State var proposal: ProposedEntry
    var onAccept: (ProposedEntry) -> Void
    var language: AppLanguage = .de
    /// Size of the ± buttons, in minutes (the time step from Settings).
    var step: Int = 15

    @State private var timeStr: String = ""

    private func t(_ key: String, _ args: String...) -> String {
        L10n.string(key, args, language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Source badge
                Text(proposal.source.in(language))
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

                Button(t("proposal.accept")) {
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
                TextField(t("proposal.ticket"), text: $proposal.ticket)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)

                StepButton(increase: false, size: 15, help: t("proposal.minutes", "\(step)")) {
                    let cur = (try? SchichtaCore.parseMinutes(timeStr)) ?? proposal.minutes
                    let next = SchichtaCore.snapDuration(cur - step, step: step)
                    timeStr = SchichtaCore.formatTime(next)
                    proposal.minutes = next
                }

                DurationInput(text: $timeStr, step: step)

                StepButton(increase: true, size: 15, help: t("proposal.minutes2", "\(step)")) {
                    let cur = (try? SchichtaCore.parseMinutes(timeStr)) ?? proposal.minutes
                    let next = SchichtaCore.snapDuration(cur + step, step: step)
                    timeStr = SchichtaCore.formatTime(next)
                    proposal.minutes = next
                }

                TextField(t("proposal.activity"), text: $proposal.description)
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
