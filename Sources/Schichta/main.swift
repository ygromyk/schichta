import Cocoa
import SwiftUI

// MARK: - Entry Point

if CommandLine.arguments.contains("--generate-icon") {
    let targetPath: String
    if let idx = CommandLine.arguments.firstIndex(of: "--generate-icon"), idx + 1 < CommandLine.arguments.count {
        targetPath = CommandLine.arguments[idx + 1]
    } else {
        targetPath = "AppIcon.iconset"
    }
    let targetURL = URL(fileURLWithPath: targetPath)
    do {
        try AppIconGenerator.generateIconSet(to: targetURL)
        print("Icon set written to: \(targetURL.path)")
        exit(0)
    } catch {
        fputs("Could not create the icon set: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else if let idx = CommandLine.arguments.firstIndex(of: "--snapshot"), idx + 1 < CommandLine.arguments.count {
    // Dev tool: renders the main views offscreen as PNGs (layout check without screen recording).
    let outDir = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    _ = NSApplication.shared
    let store = SchichtaStore()

    func render<V: View>(_ view: V, _ size: NSSize, _ name: String) {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: view)
            let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            win.appearance = NSAppearance(named: appearance)
            win.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("\(name)-\(suffix).png"))
        }
        print("\(name): fitting \(NSHostingView(rootView: view).fittingSize), rendered \(size)")
    }

    render(CheckInPopoverView(store: store, onClose: {}), NSSize(width: 380, height: 305), "popover")
    render(CheckInPopoverView(store: store, onClose: {}), NSSize(width: 380, height: 320), "checkin-panel")
    render(DatePickerPopoverContent(store: store, isPresented: .constant(true)), NSSize(width: 200, height: 230), "date-popover")
    render(MainWindowView(store: store), NSSize(width: 1220, height: 860), "main")
    render(MainWindowView(store: store), NSSize(width: 950, height: 650), "main-min")
    for tab in 0..<4 {
        store.settingsSelectedTab = tab
        render(SettingsView(store: store), NSSize(width: 720, height: 620), "settings-\(tab)")
    }
    exit(0)
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
