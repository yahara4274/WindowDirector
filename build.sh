#!/bin/zsh
# Build WindowDirector.app, install it to /Applications, and launch it (no Xcode project needed, just swiftc).
set -eu
cd "$(dirname "$0")"

APP=WindowDirector.app
rm -rf "./${APP:?}"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.yahara4274.WindowDirector</string>
  <key>CFBundleName</key><string>WindowDirector</string>
  <key>CFBundleExecutable</key><string>WindowDirector</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict>
</plist>
PLIST

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos26.0" main.swift -o "$APP/Contents/MacOS/WindowDirector" -framework AppKit -framework SwiftUI

# Sign with an Apple Development certificate if available (keeps the Accessibility permission across rebuilds); otherwise ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"

# A revoked certificate makes macOS block the app as malware, so verify the signature and fall back to ad-hoc if it fails.
if [ -n "$IDENTITY" ] && ! codesign --verify --strict "$APP" 2>/dev/null; then
  echo "warning: '$IDENTITY' failed verification (revoked or invalid?); signing ad-hoc instead" >&2
  IDENTITY=""
  codesign --force --sign - "$APP"
fi

osascript -e 'quit app "WindowDirector"' 2>/dev/null || true
sleep 1
rm -rf "/Applications/${APP:?}"
mv "$APP" /Applications/
open "/Applications/$APP"
echo "installed: /Applications/$APP (signed with: ${IDENTITY:-ad-hoc})"
