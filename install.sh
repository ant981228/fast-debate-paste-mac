#!/bin/bash
# Fast Debate Paste — one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/ant981228/fast-debate-paste-mac/main/install.sh | bash
#
# Why this exists: files downloaded by a BROWSER get macOS's quarantine
# flag, which triggers Gatekeeper ("unidentified developer") and — even
# after that — runs the app in a translocated sandbox where synthetic
# Copy/Paste silently fails. `curl` sets no quarantine flag, so an app
# installed this way needs none of the Gatekeeper dance: no right-click
# ritual, no System Settings "Open Anyway", nothing to clear.
#
# What it does: download the latest release zip, unpack, quit any running
# copy, install to /Applications, open the app. The only remaining step
# is macOS's one-time Accessibility grant, which nothing can skip.
set -euo pipefail

REPO="ant981228/fast-debate-paste-mac"
APP_NAME="Fast Debate Paste"
ZIP_URL="https://github.com/$REPO/releases/latest/download/FastDebatePaste.zip"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Sorry — Fast Debate Paste needs an Apple Silicon Mac (M1 or later)." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading the latest Fast Debate Paste ..."
curl -fsSL "$ZIP_URL" -o "$TMP/fdp.zip"

echo "==> Unpacking ..."
ditto -x -k "$TMP/fdp.zip" "$TMP/unpacked"
APP_SRC="$(find "$TMP/unpacked" -maxdepth 2 -name "$APP_NAME.app" -type d | head -1)"
if [[ -z "$APP_SRC" ]]; then
  echo "error: '$APP_NAME.app' not found inside the download." >&2
  exit 1
fi

# Quit a running copy so the bundle swap is clean (harmless if not running).
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -x FastDebatePaste 2>/dev/null || true
sleep 1

echo "==> Installing to /Applications ..."
rm -rf "/Applications/$APP_NAME.app"
ditto "$APP_SRC" "/Applications/$APP_NAME.app"
# Belt and suspenders: curl'd files carry no quarantine flag, but clear it
# anyway in case this script itself was saved via a browser first.
xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true

echo "==> Opening ..."
open "/Applications/$APP_NAME.app"

cat <<'DONE'

Installed. Look for the clipboard icon in the menu bar (top right).

First install only: macOS will ask for Accessibility permission —
  System Settings > Privacy & Security > Accessibility > turn ON
  "Fast Debate Paste". (That's what lets it press Copy/Paste for you.
  The app restarts itself once when you grant it — that's normal.)

Updating later: just run this same command again. No prompts.
DONE
