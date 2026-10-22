#!/bin/bash
# Wraps the built IRCaptureApp binary in "IR Capture.app", signs it, and zips it to dist/IR-Capture.zip.
#   scripts/make_app.sh [build-number]
# Environment (all optional):
#   CODESIGN_IDENTITY   "Developer ID Application: …" to sign for distribution (hardened runtime, timestamp,
#                       entitlements). Unset or "-" signs ad hoc, which is fine for internal test builds.
#   IRCAPTURE_CHANNEL   "release" for tagged releases; anything else is shown as a pre-release.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="IR Capture"                       # product name: Lowell decides (readiness plan, section 9)
BUILD="${1:-0}"
VERSION="$(tr -d '[:space:]' < VERSION)"
CHANNEL="${IRCAPTURE_CHANNEL:-pre-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="dist/${APP_NAME}.app"
rm -rf "$APP" dist/IR-Capture.zip && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/IRCaptureApp" "$APP/Contents/MacOS/${APP_NAME}"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>com.swellamps.ircapture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>IRCaptureChannel</key><string>${CHANNEL}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHumanReadableCopyright</key><string>© Swell Amplification LLC</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>${APP_NAME} records your microphones and the speaker reference while it plays the test sweeps, and nothing else.</string>
</dict>
</plist>
PLIST

# App icon, drawn by a small script (no binary assets in the repo).
if swift scripts/make_icon.swift "$APP/Contents/Resources/icon.png" 2>/dev/null; then
  ICONSET="dist/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$APP/Contents/Resources/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$APP/Contents/Resources/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET" "$APP/Contents/Resources/icon.png"
else
  echo "icon step skipped"
fi

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
  echo "signed ad hoc (internal build)"
else
  # Developer ID: hardened runtime and a secure timestamp are what notarization requires.
  codesign --force --options runtime --timestamp --entitlements scripts/IRCapture.entitlements --sign "$IDENTITY" "$APP"
  echo "signed with $IDENTITY"
fi
codesign --verify --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" dist/IR-Capture.zip
echo "built dist/IR-Capture.zip (version $VERSION, build $BUILD, $CHANNEL)"
