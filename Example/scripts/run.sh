#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DragonKit Sample"
BIN_NAME="DragonAppTemplate"

swift build -c debug
BIN_DIR="$(swift build -c debug --show-bin-path)"

APP="$BIN_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $BIN_NAME" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $BIN_NAME" "$APP/Contents/Info.plist"
cp -R "$BIN_DIR"/*.bundle "$APP/Contents/MacOS/" 2>/dev/null || true

# Embed Sparkle.framework (linked by DragonKitUpdates) so the relocated .app finds it at
# runtime — SwiftPM otherwise leaves it in the artifacts dir, which the moved app can't reach.
SPARKLE_FW="$(find "$(pwd)/.build" -type d -name 'Sparkle.framework' -path '*macos*' 2>/dev/null | head -1)"
if [ -n "${SPARKLE_FW:-}" ]; then
  cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
fi

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# Quit any previously-launched instance — including an older-named build (e.g. a prior
# "Dragon App.app") — so a stale menu-bar icon with an out-of-date menu doesn't linger.
pkill -f "/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
sleep 1
open "$APP"
echo "Launched $APP"
