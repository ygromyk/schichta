import AppKit
import SwiftUI

// MARK: - Schichta Theme

/// Hauptaktion: grün gefüllt, solange aktiv; deaktiviert als normaler Rahmen-Button statt blass-grüner Fläche.
struct ProminentWhenEnabled: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.buttonStyle(.borderedProminent).tint(SchichtaTheme.forestGreen)
        } else {
            content.buttonStyle(.bordered).disabled(true)
        }
    }
}

extension View {
    func prominentWhenEnabled(_ enabled: Bool) -> some View {
        modifier(ProminentWhenEnabled(enabled: enabled))
    }
}

enum SchichtaTheme {
    static let forestGreen = Color(red: 0x2b/255.0, green: 0x7a/255.0, blue: 0x5b/255.0)
    static let darkForest = Color(red: 0x1b/255.0, green: 0x52/255.0, blue: 0x3c/255.0)
    static let accentGreen = Color(red: 0x38/255.0, green: 0x9e/255.0, blue: 0x76/255.0)
    static let nsForestGreen = NSColor(srgbRed: 0x2b/255.0, green: 0x7a/255.0, blue: 0x5b/255.0, alpha: 1.0)
    static let nsDarkForest = NSColor(srgbRed: 0x1b/255.0, green: 0x52/255.0, blue: 0x3c/255.0, alpha: 1.0)
}
