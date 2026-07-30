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
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$APP_DIR/Contents/Info.plist"

INSTALL_DIR="/Applications/$APP_NAME"

if [[ "${SKIP_INSTALL:-0}" == "1" ]]; then
  echo
  echo "Built and signed: $APP_DIR (not installed, SKIP_INSTALL=1)"
  echo "Launch with: open \"$APP_DIR\""
  exit 0
fi

echo
echo "Installing to $INSTALL_DIR..."

BUILT_BIN="$APP_DIR/Contents/MacOS/OwnscribeMenuBar"
if [ ! -f "$BUILT_BIN" ] || [ ! -x "$BUILT_BIN" ]; then
  echo "Error: built binary not found or not executable: $BUILT_BIN" >&2
  exit 2
fi

MENUBAR_BIN="$INSTALL_DIR/Contents/MacOS/OwnscribeMenuBar"
if pgrep -f "$MENUBAR_BIN" >/dev/null 2>&1; then
  echo "Quitting the running instance first..."
  pkill -f "$MENUBAR_BIN" || true
  for i in {1..10}; do
    if ! pgrep -f "$MENUBAR_BIN"; then
      break
    fi
    sleep 0.2
  done
  if pgrep -fq "$MENUBAR_BIN"; then
    echo "Warning: installed app still running after 2s" >&2
  fi
fi

rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" /Applications/
codesign --verify --deep --strict "$INSTALL_DIR"

INSTALLED_BIN="$INSTALL_DIR/Contents/MacOS/OwnscribeMenuBar"
if [ ! -f "$INSTALLED_BIN" ] || [ ! -x "$INSTALLED_BIN" ]; then
  echo "Error: installed binary not found after copy: $INSTALLED_BIN" >&2
  echo "The app was installed to $INSTALL_DIR but the binary is missing." >&2
  exit 2
fi

if ! cmp -s "$INSTALLED_BIN" "$BUILT_BIN"; then
  echo "Error: installed binary content differs from built binary." >&2
  echo "The app is installed at $INSTALL_DIR but may be stale." >&2
  echo "Do NOT launch from $APP_DIR — use: open \"$INSTALL_DIR\"" >&2
  exit 1
fi

echo
echo "Built, signed and installed: $INSTALL_DIR"
echo "Launch with: open \"$INSTALL_DIR\""
