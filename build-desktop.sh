#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Zeitbuch.app"
rm -rf "$APP/Contents/Resources"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Kompiliere Zeitbuch (SwiftUI + AppKit + UserNotifications)..."
xcrun swiftc -swift-version 5 -O -module-cache-path /private/tmp/zeitbuch-swift-cache \
    -framework Cocoa -framework SwiftUI -framework UserNotifications -framework Security \
    Desktop.swift -o "$APP/Contents/MacOS/Zeitbuch"

echo "Erzeuge App-Icon (AppIcon.icns)..."
ICONSET="/private/tmp/Zeitbuch.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/Zeitbuch" --generate-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cp targets/*.example.json "$APP/Contents/Resources/"

echo "Schreibe Info.plist..."
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Zeitbuch</string>
<key>CFBundleIdentifier</key><string>local.zeitbuch</string>
<key>CFBundleName</key><string>Zeitbuch</string>
<key>CFBundleDisplayName</key><string>Zeitbuch</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "Signiere Zeitbuch.app..."
xattr -cr "$APP"
codesign --force --sign - "$APP"
swift -e 'import Cocoa
if let img = NSImage(contentsOfFile: "Zeitbuch.app/Contents/Resources/AppIcon.icns") {
    NSWorkspace.shared.setIcon(img, forFile: "Zeitbuch.app", options: [])
}'
touch "$APP"
echo "Registriere Zeitbuch.app bei LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP" || true
echo "Desktop-App erfolgreich gebaut: $PWD/$APP"
