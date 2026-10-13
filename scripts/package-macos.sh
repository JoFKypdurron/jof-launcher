#!/bin/bash
set -euo pipefail

# Ensure we are in the project root
cd "$(dirname "$0")/.."

APP_NAME="JoF Launcher.app"
VOLUME_NAME="JoF Launcher"
APP_DIR="build/macos/Build/Products/Release/$APP_NAME"
OUTPUT_NAME="jof-launcher-macos.dmg"
STAGING_DIR="build/macos/dmg-staging"

if [ ! -d "$APP_DIR" ]; then
    echo "Error: App directory not found at $APP_DIR"
    echo "Please run 'flutter build macos --release' first."
    exit 1
fi

echo "Creating $OUTPUT_NAME from $APP_DIR..."

# Stage the disk image contents: the app, a drop target for /Applications and
# first-launch instructions (the build is unsigned, so Gatekeeper needs a hand).
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# ditto (not cp) so symlinks, extended attributes and the ad-hoc code signature
# survive the copy intact.
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME"

# A stray quarantine flag on the build machine would be baked into the image.
xattr -dr com.apple.quarantine "$STAGING_DIR/$APP_NAME" 2>/dev/null || true

ln -s /Applications "$STAGING_DIR/Applications"

cat > "$STAGING_DIR/Read Me First.txt" <<'EOF'
JoF Launcher for macOS
======================

Installing
----------
Drag "JoF Launcher" onto the Applications folder in this window.

First launch
------------
This build is not signed with an Apple Developer ID, so macOS blocks it the
first time. This is expected. To allow it:

  1. Open JoF Launcher from Applications. macOS refuses to open it.
  2. Go to System Settings > Privacy & Security.
  3. Scroll to the Security section. You will see a message about
     "JoF Launcher" being blocked. Click "Open Anyway".
  4. Confirm with your password or Touch ID.

You only need to do this once per installed version.

If you prefer the Terminal, this achieves the same thing:

  xattr -dr com.apple.quarantine "/Applications/JoF Launcher.app"

Note: macOS may ask again for permission to access folders such as Documents
or Downloads after each update. That is a side effect of the app being
unsigned, and granting it is safe.
EOF

# Finder litter in the staging folder ends up visible inside the image.
find "$STAGING_DIR" -name '.DS_Store' -delete

# UDZO = compressed, read-only. -ov overwrites a stale image from a prior run.
rm -f "$OUTPUT_NAME"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_NAME"

rm -rf "$STAGING_DIR"

echo "Done! $OUTPUT_NAME created in the project root."
