#!/bin/bash
# Build Fast Debate Paste and assemble a menu-bar .app bundle.
#
#   ./build.sh           → build + package into ./dist/Fast Debate Paste.app
#   ./build.sh install   → also copy the app into /Applications
#
# Requires the Swift toolchain (Xcode or Command Line Tools).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Fast Debate Paste"
BUNDLE_ID="com.fastdebatepaste.app"
VERSION="1.7.0"
BIN_NAME="FastDebatePaste"

echo "==> Building (release)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$BIN_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: built binary not found at $BIN_PATH" >&2
  exit 1
fi

APP_DIR="dist/$APP_NAME.app"
echo "==> Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Fast Debate Paste</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <!-- The CardMirror bridge is plain HTTP on 127.0.0.1. This
             exempts loopback / local addresses from App Transport
             Security so URLSession can reach it. -->
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# Prefer a stable self-signed identity (see setup-signing.sh) so the
# Accessibility grant survives rebuilds. Fall back to ad-hoc, which works
# but loses the grant on every rebuild.
SIGN_IDENTITY="Fast Debate Paste Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "==> Code signing with stable identity: $SIGN_IDENTITY"
  SIGN_ARG="$SIGN_IDENTITY"
else
  echo "==> Code signing (ad-hoc; run ./setup-signing.sh for a persistent Accessibility grant)"
  SIGN_ARG="-"
fi
codesign --force --sign "$SIGN_ARG" \
  --identifier "$BUNDLE_ID" \
  "$APP_DIR" >/dev/null 2>&1 || {
    echo "warning: codesign failed; the app will still run but may re-prompt for Accessibility" >&2
  }

echo "==> Built: $APP_DIR"

if [[ "${1:-}" == "install" ]]; then
  echo "==> Installing to /Applications..."
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
  echo "==> Installed: /Applications/$APP_NAME.app"
fi

echo "Done. Launch it, then grant Accessibility when prompted"
echo "(System Settings → Privacy & Security → Accessibility)."
