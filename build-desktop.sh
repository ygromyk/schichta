#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Schichta.app"
rm -rf "$APP/Contents/Resources"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Kompiliere Schichta (SwiftUI + AppKit + UserNotifications)..."
xcrun swiftc -swift-version 5 -O -module-cache-path /private/tmp/schichta-swift-cache \
    -framework Cocoa -framework SwiftUI -framework UserNotifications -framework Security \
    Desktop.swift -o "$APP/Contents/MacOS/Schichta"

echo "Erzeuge App-Icon (AppIcon.icns)..."
ICONSET="/private/tmp/Schichta.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/Schichta" --generate-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cp targets/*.example.json "$APP/Contents/Resources/"

echo "Schreibe Info.plist..."
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Schichta</string>
<key>CFBundleIdentifier</key><string>local.schichta</string>
<key>CFBundleName</key><string>Schichta</string>
<key>CFBundleDisplayName</key><string>Schichta</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "Signiere Schichta.app..."
xattr -cr "$APP"
codesign --force --sign - "$APP"
swift -e 'import Cocoa
if let img = NSImage(contentsOfFile: "Schichta.app/Contents/Resources/AppIcon.icns") {
    NSWorkspace.shared.setIcon(img, forFile: "Schichta.app", options: [])
}'
touch "$APP"
echo "Registriere Schichta.app bei LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP" || true
echo "Desktop-App erfolgreich gebaut: $PWD/$APP"
