#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="MeetingScribeDev"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_NAME="MeetingScribe.app"
APP_DIR="$REPO_ROOT/dist/$APP_NAME"

if ! security find-identity -v -p codesigning | grep -q "\"$CERT_NAME\""; then
  echo "Error: no \"$CERT_NAME\" code-signing identity in the login keychain." >&2
  echo "Create it once with: bash scripts/setup-codesign-identity.sh" >&2
  exit 1
fi

echo "Building ownscribe-audio (release)..."
(cd "$SCRIPT_DIR" && swift build -c release --product ownscribe-audio)

echo "Building OwnscribeMenuBar (release)..."
(cd "$SCRIPT_DIR" && swift build -c release --product OwnscribeMenuBar)

echo "Assembling $APP_NAME..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$SCRIPT_DIR/.build/release/OwnscribeMenuBar" "$APP_DIR/Contents/MacOS/OwnscribeMenuBar"
cp "$SCRIPT_DIR/.build/release/ownscribe-audio" "$APP_DIR/Contents/MacOS/ownscribe-audio"
cp "$SCRIPT_DIR/Resources/MenuBarApp-Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Signing ownscribe-audio with $CERT_NAME..."
codesign --force \
  --sign "$CERT_NAME" \
  --options runtime \
  --entitlements "$SCRIPT_DIR/Resources/MenuBarApp.entitlements" \
  "$APP_DIR/Contents/MacOS/ownscribe-audio"

echo "Signing OwnscribeMenuBar with $CERT_NAME..."
codesign --force \
  --sign "$CERT_NAME" \
  --options runtime \
  --entitlements "$SCRIPT_DIR/Resources/MenuBarApp.entitlements" \
  "$APP_DIR/Contents/MacOS/OwnscribeMenuBar"

echo "Signing $APP_NAME bundle with $CERT_NAME..."
codesign --force \
  --sign "$CERT_NAME" \
  --options runtime \
  --entitlements "$SCRIPT_DIR/Resources/MenuBarApp.entitlements" \
  "$APP_DIR"

echo
echo "Verifying signature..."
codesign -dvvv "$APP_DIR" 2>&1

echo
echo "Verifying entitlements..."
codesign -d --entitlements - "$APP_DIR" 2>&1

echo
echo "Verifying Info.plist keys..."
/usr/libexec/PlistBuddy -c "Print :NSAudioCaptureUsageDescription" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP_DIR/Contents/Info.plist"

INSTALL_DIR="/Applications/$APP_NAME"

if [[ "${SKIP_INSTALL:-0}" == "1" ]]; then
  echo
  echo "Built and signed: $APP_DIR (not installed, SKIP_INSTALL=1)"
  echo "Launch with: open \"$APP_DIR\""
  exit 0
fi

echo
echo "Installing to $INSTALL_DIR..."
if pgrep -f "$INSTALL_DIR/Contents/MacOS/" >/dev/null 2>&1; then
  echo "Quitting the running instance first..."
  pkill -f "$INSTALL_DIR/Contents/MacOS/" || true
  sleep 1
fi
rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" /Applications/
codesign --verify --deep --strict "$INSTALL_DIR"

INSTALLED_BIN=$(find "$INSTALL_DIR/Contents/MacOS" -type f -perm +111 -name '*MenuBar*' | head -1)
BUILT_BIN=$(find "$APP_DIR/Contents/MacOS" -type f -perm +111 -name '*MenuBar*' | head -1)
if ! cmp -s "$INSTALLED_BIN" "$BUILT_BIN"; then
  echo "Error: the installed binary differs from the one just built." >&2
  exit 1
fi

echo
echo "Built, signed and installed: $INSTALL_DIR"
echo "Launch with: open \"$INSTALL_DIR\""
