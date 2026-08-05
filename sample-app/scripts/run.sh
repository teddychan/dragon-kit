#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Dragon Sample App — local debug build. Per the dragon-mac-ops convention the debug build
# gets its OWN identity ("Dragon Sample App Debug" / a .debug bundle id) so its TCC grants
# and settings never collide with an installed release copy (brew install --cask ...).
APP_NAME="Dragon Sample App Debug"
BIN_NAME="DragonAppTemplate"
DEBUG_ID="com.dragonapp.dragon-sample-app.debug"
# A stable self-signed identity of this exact name (Keychain Access → Certificate Assistant
# → Create a Certificate → type "Code Signing") makes the Accessibility grant persist across
# rebuilds. Without it we fall back to ad-hoc, which re-prompts each build.
SIGN_IDENTITY="Dragon Sample App Debug"

swift build -c debug
BIN_DIR="$(swift build -c debug --show-bin-path)"

APP="$BIN_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"

# Re-id the main bundle to the .debug identity so it runs safely beside an installed release.
PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :CFBundleIdentifier $DEBUG_ID" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist" 2>/dev/null \
  || "$PB" -c "Add :CFBundleDisplayName string $APP_NAME" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleExecutable $BIN_NAME" "$APP/Contents/Info.plist" 2>/dev/null \
  || "$PB" -c "Add :CFBundleExecutable string $BIN_NAME" "$APP/Contents/Info.plist"

# Build number = git commit count (monotonic) so About shows a real per-build number
# instead of the placeholder "1".
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
"$PB" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist" 2>/dev/null \
  || "$PB" -c "Add :CFBundleVersion string $BUILD" "$APP/Contents/Info.plist"

# Copy every SwiftPM resource bundle next to the binary: DragonKit_DragonKit.bundle (the
# kit's strings) AND DragonAppTemplate_DragonAppTemplate.bundle (the app's own strings,
# resolved at runtime via LocalizationManager.appStringsBundle = .module).
cp -R "$BIN_DIR"/*.bundle "$APP/Contents/MacOS/" 2>/dev/null || true

# Embed Sparkle.framework (linked by DragonKitUpdates) so the relocated .app finds it at
# runtime — SwiftPM otherwise leaves it in the artifacts dir, which the moved app can't reach.
SPARKLE_FW="$(find "$(pwd)/.build" -type d -name 'Sparkle.framework' -path '*macos*' 2>/dev/null | head -1)"
if [ -n "${SPARKLE_FW:-}" ]; then
  cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
fi

# Prefer the stable self-signed identity so Accessibility/Screen-Recording grants survive
# rebuilds; otherwise ad-hoc sign and tell the user how to make grants persist.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" >/dev/null 2>&1 \
    && echo "Signed with stable identity '$SIGN_IDENTITY' (grants persist across rebuilds)."
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "note: ad-hoc signed — macOS re-prompts for Accessibility after each rebuild."
  echo "      To persist grants, create a self-signed Code Signing certificate named"
  echo "      '$SIGN_IDENTITY' in Keychain Access (Certificate Assistant → Create a Certificate)."
fi

# Quit any previously-launched debug instance so a stale menu-bar icon doesn't linger.
pkill -f "/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
sleep 1
open "$APP"
echo "Launched $APP"
