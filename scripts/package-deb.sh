#!/bin/bash

set -euo pipefail

# Ensure we are in the project root
cd "$(dirname "$0")/.."

APP_NAME="JoF Launcher"
PACKAGE_NAME="jof-launcher"
INSTALL_DIR="/opt/jof-launcher"
BUNDLE_DIR="build/linux/x64/release/bundle"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Error: Bundle directory not found at $BUNDLE_DIR"
  echo "Please run 'flutter build linux --release' first."
  exit 1
fi

if [ ! -f "$BUNDLE_DIR/jof-launcher" ]; then
  echo "Error: Expected executable '$BUNDLE_DIR/jof-launcher' not found."
  echo "Check your Linux build output and update scripts/package-deb.sh if the name differs."
  exit 1
fi

VERSION_FROM_PUBSPEC="$(grep -E '^version:' pubspec.yaml | head -n1 | awk '{print $2}')"
VERSION="${VERSION:-$VERSION_FROM_PUBSPEC}"

# Make version Debian-friendly (e.g. strip leading 'v' and replace invalid chars)
VERSION="${VERSION#v}"
VERSION="${VERSION%-launcher}"
VERSION="$(printf '%s' "$VERSION" | tr -c '0-9A-Za-z.+~:-' '-')"

ARCH="${ARCH:-amd64}"

WORK_DIR="build/deb"
ROOT_DIR="$WORK_DIR/root"
OUTPUT_DEB="$WORK_DIR/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"

rm -rf "$WORK_DIR"
mkdir -p "$ROOT_DIR"

# Payload
mkdir -p "$ROOT_DIR$INSTALL_DIR"
cp -r "$BUNDLE_DIR"/* "$ROOT_DIR$INSTALL_DIR/"

# CLI launcher
mkdir -p "$ROOT_DIR/usr/bin"
cat > "$ROOT_DIR/usr/bin/$PACKAGE_NAME" <<EOF
#!/bin/sh
exec $INSTALL_DIR/jof-launcher "\$@"
EOF
chmod 0755 "$ROOT_DIR/usr/bin/$PACKAGE_NAME"

# Desktop entry
mkdir -p "$ROOT_DIR/usr/share/applications"
cat > "$ROOT_DIR/usr/share/applications/$PACKAGE_NAME.desktop" <<EOF
[Desktop Entry]
Name=$APP_NAME
Exec=$PACKAGE_NAME
Terminal=false
Type=Application
Categories=Game;Utility;
Icon=$PACKAGE_NAME
EOF

# Icon
mkdir -p "$ROOT_DIR/usr/share/icons/hicolor/256x256/apps"
cp assets/jof_logo.png "$ROOT_DIR/usr/share/icons/hicolor/256x256/apps/$PACKAGE_NAME.png"

# Control
mkdir -p "$ROOT_DIR/DEBIAN"
MAINTAINER_NAME="${MAINTAINER_NAME:-JOF}"
MAINTAINER_EMAIL="${MAINTAINER_EMAIL:-noreply@github.com}"

cat > "$ROOT_DIR/DEBIAN/control" <<EOF
Package: $PACKAGE_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: $MAINTAINER_NAME <$MAINTAINER_EMAIL>
Depends: libgtk-3-0, libstdc++6, libgcc-s1
Description: $APP_NAME (Flutter)
 Desktop launcher for JoF.
EOF

# Debian packages require specific permissions under DEBIAN
chmod 0755 "$ROOT_DIR/DEBIAN"
chmod 0644 "$ROOT_DIR/DEBIAN/control"

# Build
dpkg-deb --build "$ROOT_DIR" "$OUTPUT_DEB" >/dev/null

echo "Done! Created $OUTPUT_DEB"
