#!/bin/bash
# Wraps the built IRCaptureApp binary in "IR Capture.app", signs it ad hoc,
# and zips it to dist/IR-Capture.zip. Usage: scripts/make_app.sh [build-number]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${1:-0}"
VERSION="0.1.${BUILD}"
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="dist/IR Capture.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/IRCaptureApp" "$APP/Contents/MacOS/IR Capture"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>IR Capture</string>
  <key>CFBundleDisplayName</key><string>IR Capture</string>
  <key>CFBundleExecutable</key><string>IR Capture</string>
  <key>CFBundleIdentifier</key><string>com.swellamps.ircapture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>IR Capture records your microphones and the speaker reference tap while it plays the test sweeps.</string>
</dict>
</plist>
EOF

# App icon, drawn by a small script (no binary assets in the repo).
if swift scripts/make_icon.swift "$APP/Contents/Resources/icon.png" 2>/dev/null; then
  ICONSET="dist/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$APP/Contents/Resources/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$APP/Contents/Resources/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET" "$APP/Contents/Resources/icon.png"
else
  echo "icon step skipped"
fi

codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
ditto -c -k --keepParent "$APP" dist/IR-Capture.zip
echo "built dist/IR-Capture.zip (version $VERSION)"
