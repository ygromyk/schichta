#!/bin/bash
# Baut Schichta.app. Optionale Umgebungsvariablen (für Releases/CI):
#   APP=pfad/Schichta.app   Ausgabeort (Standard: ./Schichta.app)
#   VERSION=1.2.0           CFBundleShortVersionString (Standard: 1.0)
#   BUILD_NUMBER=42         CFBundleVersion (Standard: 1)
#   UNIVERSAL=1             arm64 + x86_64 statt nur der eigenen Architektur
#   SIGN_IDENTITY="Developer ID Application: …"  statt Ad-hoc-Signatur (mit Hardened Runtime)
set -euo pipefail
cd "$(dirname "$0")"
APP="${APP:-Schichta.app}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
MIN_MACOS="14.0"  # onChange(of:initial:_:) braucht macOS 14
rm -rf "$APP/Contents/Resources"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SWIFTC=(xcrun swiftc -swift-version 5 -O -module-cache-path /private/tmp/schichta-swift-cache
        -framework Cocoa -framework SwiftUI -framework UserNotifications -framework Security)
echo "Kompiliere Schichta $VERSION (SwiftUI + AppKit + UserNotifications)..."
if [ "${UNIVERSAL:-}" = "1" ]; then
    BUILD_DIR="$(mktemp -d)"
    for ARCH in arm64 x86_64; do
        "${SWIFTC[@]}" -target "$ARCH-apple-macosx$MIN_MACOS" Desktop.swift -o "$BUILD_DIR/Schichta-$ARCH"
    done
    lipo -create "$BUILD_DIR/Schichta-arm64" "$BUILD_DIR/Schichta-x86_64" -output "$APP/Contents/MacOS/Schichta"
    rm -rf "$BUILD_DIR"
else
    "${SWIFTC[@]}" Desktop.swift -o "$APP/Contents/MacOS/Schichta"
fi

echo "Erzeuge App-Icon (AppIcon.icns)..."
ICONSET="$(mktemp -d)/Schichta.iconset"
"$APP/Contents/MacOS/Schichta" --generate-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cp targets/*.example.json "$APP/Contents/Resources/"

echo "Schreibe Info.plist..."
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Schichta</string>
<key>CFBundleIdentifier</key><string>local.schichta</string>
<key>CFBundleName</key><string>Schichta</string>
<key>CFBundleDisplayName</key><string>Schichta</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "Signiere $APP..."
xattr -cr "$APP"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    # Hardened Runtime + sichere Zeitstempel sind Voraussetzung für die Notarisierung.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

# Nur lokal: Finder-Icon setzen und bei LaunchServices registrieren. setIcon legt eine
# Icon-Datei ins Bundle und würde eine Release-Signatur ungültig machen.
if [ -z "${CI:-}" ] && [ "$SIGN_IDENTITY" = "-" ]; then
    APP_PATH="$APP" swift -e 'import Cocoa
    let app = ProcessInfo.processInfo.environment["APP_PATH"]!
    if let img = NSImage(contentsOfFile: app + "/Contents/Resources/AppIcon.icns") {
        NSWorkspace.shared.setIcon(img, forFile: app, options: [])
    }'
    touch "$APP"
    echo "Registriere $APP bei LaunchServices..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")" || true
fi
echo "Desktop-App erfolgreich gebaut: $APP"
