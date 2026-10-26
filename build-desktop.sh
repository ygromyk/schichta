#!/bin/bash
# Builds Schichta.app. Optional environment variables (for releases/CI):
#   APP=path/Schichta.app   output path (default: ./Schichta.app)
#   VERSION=1.2.0           CFBundleShortVersionString (default: 1.0)
#   BUILD_NUMBER=42         CFBundleVersion (default: 1)
#   UNIVERSAL=1             arm64 + x86_64 instead of only the host architecture
#   SIGN_IDENTITY="Developer ID Application: …"  instead of ad-hoc signing (with hardened runtime)
set -euo pipefail
cd "$(dirname "$0")"
APP="${APP:-Schichta.app}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
MIN_MACOS="14.0"  # onChange(of:initial:_:) needs macOS 14
rm -rf "$APP/Contents/Resources"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling Schichta $VERSION (swift build)..."
if [ "${UNIVERSAL:-}" = "1" ]; then
    # Build per architecture and merge with lipo: `--arch a --arch b` needs Xcode, this works with the Command Line Tools.
    BINARIES=()
    for ARCH in arm64 x86_64; do
        BUILD=(swift build -c release --triple "$ARCH-apple-macosx$MIN_MACOS")
        "${BUILD[@]}"
        BINARIES+=("$("${BUILD[@]}" --show-bin-path)/Schichta")
    done
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Schichta"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/Schichta" "$APP/Contents/MacOS/Schichta"
fi

echo "Creating app icon (AppIcon.icns)..."
ICONSET="$(mktemp -d)/Schichta.iconset"
"$APP/Contents/MacOS/Schichta" --generate-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cp targets/*.example.json "$APP/Contents/Resources/"

echo "Writing Info.plist..."
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

echo "Signing $APP..."
xattr -cr "$APP"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    # Hardened runtime + secure timestamp are required for notarization.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

# Local builds only: set the Finder icon and register with LaunchServices. setIcon writes an
# icon file into the bundle, which would invalidate a release signature.
if [ -z "${CI:-}" ] && [ "$SIGN_IDENTITY" = "-" ]; then
    APP_PATH="$APP" swift -e 'import Cocoa
    let app = ProcessInfo.processInfo.environment["APP_PATH"]!
    if let img = NSImage(contentsOfFile: app + "/Contents/Resources/AppIcon.icns") {
        NSWorkspace.shared.setIcon(img, forFile: app, options: [])
    }'
    touch "$APP"
    echo "Registering $APP with LaunchServices..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")" || true
fi
echo "Built: $APP"
