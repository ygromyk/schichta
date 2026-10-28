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

// MARK: - Duration Input

/// Duration as two fields, hours : minutes. Tab moves from hours to minutes; a blank
/// field becomes 00 when it loses focus; ↑/↓ change hours by 1 and minutes by `step`.
struct DurationInput: View {
    /// "HH:MM", the format `SchichtaCore.formatTime` writes and `parseMinutes` reads.
    @Binding var text: String
    /// Minute step for ↑/↓ in the minutes field (the time step from Settings).
    var step: Int = 15
    var fontSize: CGFloat = 12
    var help: String = ""
    /// Called on Enter and when focus leaves both fields.
    var onCommit: () -> Void = {}

    private enum Part: Hashable { case hours, minutes }
    @FocusState private var focus: Part?
    @State private var hours = "00"
    @State private var minutes = "00"

    var body: some View {
        HStack(spacing: 0) {
            field($hours, part: .hours)
            Text(":")
            field($minutes, part: .minutes)
        }
        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(focus != nil ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(focus != nil ? SchichtaTheme.forestGreen : Color(nsColor: .separatorColor), lineWidth: focus != nil ? 1.5 : 0.5)
        )
        .help(help)
        .onAppear { load(text) }
        .onChange(of: text) { _, new in
            // Outside changes (± buttons, presets) only while the user isn't typing.
            if focus == nil { load(new) }
        }
        .onChange(of: focus) { _, new in
            // Re-format on every focus move: blank → 00, 75 minutes → 01:15.
            load(SchichtaCore.formatTime(totalMinutes))
            publish()
            if new == nil { onCommit() }
        }
    }

    private func field(_ value: Binding<String>, part: Part) -> some View {
        TextField("00", text: value)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .frame(width: fontSize * 1.5)
            .focused($focus, equals: part)
            .onChange(of: value.wrappedValue) { _, new in
                let digits = String(new.filter(\.isNumber).prefix(2))
                if digits != new { value.wrappedValue = digits }
                publish()
            }
            .onKeyPress(.upArrow) { bump(part, by: 1); return .handled }
            .onKeyPress(.downArrow) { bump(part, by: -1); return .handled }
            .onSubmit {
                load(SchichtaCore.formatTime(totalMinutes))
                publish()
                onCommit()
            }
    }

    private var totalMinutes: Int { (Int(hours) ?? 0) * 60 + (Int(minutes) ?? 0) }

    private func bump(_ part: Part, by delta: Int) {
        let cur = totalMinutes
        let next: Int
        switch part {
        case .hours:
            next = cur + delta * 60
            guard next >= 0, next <= 1440 else { return NSSound.beep() }
        case .minutes:
            // Same snapping as the ± buttons, so 0:45 ↑ carries over to 1:00.
            next = SchichtaCore.snapDuration(cur + delta * step, step: step)
        }
        load(SchichtaCore.formatTime(next))
        publish()
    }

    private func load(_ s: String) {
        let total = (try? SchichtaCore.parseMinutes(s)) ?? 0
        hours = String(format: "%02d", total / 60)
        minutes = String(format: "%02d", total % 60)
    }

    private func publish() {
        let formatted = SchichtaCore.formatTime(totalMinutes)
        if text != formatted { text = formatted }
    }
}

// MARK: - Inline Duration Field

struct InlineDurationField: View {
    let entry: Entry
    @ObservedObject var store: SchichtaStore
    @State private var text: String = ""

    var body: some View {
        DurationInput(
            text: $text, step: store.timeStepMinutes, fontSize: 13,
            help: store.t("controls.typeTheDurationTabMoves"),
            onCommit: commitChange
        )
        .onAppear {
            text = SchichtaCore.formatTime(entry.minutes)
        }
        .onChange(of: entry.minutes) { _, newMin in
            text = SchichtaCore.formatTime(newMin)
        }
    }

    private func commitChange() {
        guard let typed = try? SchichtaCore.parseMinutes(text) else {
            text = SchichtaCore.formatTime(entry.minutes)
            return
        }
        let mins = store.snapDuration(typed)
        if mins != entry.minutes {
            store.setEntryMinutes(id: entry.id, minutes: mins)
        }
        text = SchichtaCore.formatTime(mins)
    }
}
