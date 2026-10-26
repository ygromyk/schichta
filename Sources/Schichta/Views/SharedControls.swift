import AppKit
import SwiftUI

// MARK: - Shared Controls

/// −/+ button next to duration and interval fields.
struct StepButton: View {
    let increase: Bool
    var size: CGFloat = 15
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: increase ? "plus.circle.fill" : "minus.circle.fill")
                .font(.system(size: size))
                .foregroundColor(increase ? SchichtaTheme.forestGreen : .secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension View {
    /// Frame of the four tiles in the metrics bar.
    func tileStyle() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    /// Colored banner (morning / end-of-day prompt) below the header.
    func bannerStyle(_ color: Color) -> some View {
        padding(10)
            .background(color.opacity(0.12))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.35), lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Inline Duration Field

struct InlineDurationField: View {
    let entry: Entry
    @ObservedObject var store: SchichtaStore
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("0:15", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 52)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isFocused ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .controlBackgroundColor).opacity(0.8))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isFocused ? SchichtaTheme.forestGreen : Color(nsColor: .separatorColor), lineWidth: isFocused ? 1.5 : 0.5)
            )
            .focused($isFocused)
            .onSubmit {
                commitChange()
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commitChange()
                }
            }
            .onAppear {
                text = SchichtaCore.formatTime(entry.minutes)
            }
            .onChange(of: entry.minutes) { _, newMin in
                if !isFocused {
                    text = SchichtaCore.formatTime(newMin)
                }
            }
            .help(store.t("Dauer direkt eintippen (z. B. 1:15 oder 45m) und mit Enter bestätigen", "Type duration directly (e.g. 1:15 or 45m) and press Enter to confirm"))
    }

    private func commitChange() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            text = SchichtaCore.formatTime(entry.minutes)
            return
        }
        if let typed = try? SchichtaCore.parseMinutes(trimmed) {
            let mins = store.snapDuration(typed)
            if mins != entry.minutes {
                store.setEntryMinutes(id: entry.id, minutes: mins)
            }
            text = SchichtaCore.formatTime(mins)
        } else {
            NSSound.beep()
            text = SchichtaCore.formatTime(entry.minutes)
        }
    }
}
