#!/bin/bash
# Build a clean, foolproof distribution package for sharing the app with
# someone who is NOT going to build it themselves.
#
#   ./package-for-sharing.sh   → share/FastDebatePaste.zip
#
# Differences from build.sh (which targets local dev on YOUR machine):
#   * Signs with the STABLE self-signed identity (setup-signing.sh) when
#     present, falling back to ad-hoc. TCC's designated requirement embeds
#     the certificate hash from the signature itself — the cert does NOT
#     need to exist in the friend's keychain — so signing every release
#     with the same cert keeps their Accessibility grant across UPDATES.
#     (The previous always-ad-hoc approach had this backwards: ad-hoc
#     identity changes every build, so each update looked like a brand-new
#     app to TCC and the grant was lost.)
#   * Strips ALL extended attributes (Dropbox/Finder/quarantine/provenance)
#     BEFORE signing, so the signature survives the zip round-trip.
#   * Zips with ditto (no resource forks / __MACOSX junk).
#   * Bundles an installer.command that moves the app to /Applications and
#     removes quarantine — the step that prevents App Translocation, which
#     is the usual reason "copy" silently fails on a fresh machine. (The
#     curl-based install.sh needs none of that; the .command is the
#     fallback for people handed the zip directly.)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Fast Debate Paste"

echo "==> Building a fresh release bundle ..."
# build.sh assembles dist/<app> and signs it. We re-sign below (after the
# xattr strip) so the signature is computed over exactly what ships.
./build.sh >/dev/null

SRC_APP="dist/$APP_NAME.app"
if [[ ! -d "$SRC_APP" ]]; then
  echo "error: $SRC_APP not found after build" >&2
  exit 1
fi

STAGE="share/$APP_NAME"
OUT_APP="$STAGE/$APP_NAME.app"
echo "==> Staging a clean copy ..."
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$SRC_APP" "$OUT_APP"

echo "==> Stripping extended attributes (Dropbox/Finder/quarantine) ..."
xattr -cr "$OUT_APP"

# Stable identity → friends' Accessibility grants survive updates. Ad-hoc
# fallback still works, but every release re-prompts (see header comment).
SIGN_IDENTITY="Fast Debate Paste Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "==> Signing with stable identity: $SIGN_IDENTITY"
  SIGN_ARG="$SIGN_IDENTITY"
else
  echo "==> WARNING: stable identity not found (run ./setup-signing.sh)." >&2
  echo "    Falling back to ad-hoc — updates will re-prompt for Accessibility." >&2
  SIGN_ARG="-"
fi
codesign --force --deep --sign "$SIGN_ARG" \
  --identifier "com.fastdebatepaste.app" \
  "$OUT_APP"
codesign --verify --strict "$OUT_APP" && echo "    signature OK"

echo "==> Writing installer.command ..."
cat > "$STAGE/Install Fast Debate Paste.command" <<'INSTALLER'
#!/bin/bash
# Double-click this to install Fast Debate Paste correctly.
# It moves the app to /Applications and clears the macOS "quarantine" flag,
# which is what stops the app from working (it makes Copy silently fail).
cd "$(dirname "$0")"
APP="Fast Debate Paste.app"
DEST="/Applications/$APP"

echo "Installing $APP ..."
if [[ ! -d "$APP" ]]; then
  echo "ERROR: could not find $APP next to this installer."
  echo "Make sure you unzipped the whole folder and run this from inside it."
  read -n 1 -s -r -p "Press any key to close."
  exit 1
fi

rm -rf "$DEST"
cp -R "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "Done. Opening it now ..."
open "$DEST"
echo
echo "Last step: grant Accessibility permission when asked"
echo "(System Settings > Privacy & Security > Accessibility)."
echo
read -n 1 -s -r -p "Press any key to close this window."
INSTALLER
chmod +x "$STAGE/Install Fast Debate Paste.command"

echo "==> Copying the instructions ..."
cp "How to Run Fast Debate Paste.txt" "$STAGE/How to Run Fast Debate Paste.txt"

echo "==> Zipping with ditto ..."
# Space-free zip name → a stable GitHub release-asset URL
# (…/releases/latest/download/FastDebatePaste.zip) for install.sh.
# The folder INSIDE keeps the friendly name.
ZIP="share/FastDebatePaste.zip"
rm -f "$ZIP"
# keepParent keeps the nicely-named "Fast Debate Paste" folder, so the friend
# unzips one folder holding the app, the installer, and the instructions.
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"

rm -rf "$STAGE"
echo "==> Done: $ZIP"
echo "    Contains: the app (stable-signed, xattrs stripped),"
echo "    the double-click installer, and the instructions."
