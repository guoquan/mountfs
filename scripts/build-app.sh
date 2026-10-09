#!/bin/bash
set -euo pipefail
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT"
if [ "$(uname -s)" != Darwin ]; then
    printf 'The menu bar app must be built on macOS with Xcode command line tools.\n' >&2
    exit 1
fi
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
VERSION=$(bash mountfs.sh --version)
APP="$PROJECT_ROOT/dist/mouNTFS-$VERSION.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MountFS" "$APP/Contents/MacOS/mouNTFS"
cp "$BIN_DIR/MountFSIdentity" "$APP/Contents/MacOS/mountfs-identity"
cp mountfs.sh "$APP/Contents/Resources/mountfs.sh"
ICON_WORK=$(mktemp -d "${TMPDIR:-/tmp}/mountfs-icons.XXXXXXXX")
trap 'rm -rf "$ICON_WORK"' EXIT
swiftc Sources/MountFSApp/BrandIcon.swift scripts/generate-icons.swift -o "$ICON_WORK/generate-icons"
"$ICON_WORK/generate-icons" "$ICON_WORK/AppIcon.iconset"
/usr/bin/iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp scripts/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signing is for local development only. Public distribution requires
# a Developer ID signature and Apple notarization.
/usr/bin/codesign --force --deep --sign - "$APP"
printf 'Built local development app: %s\n' "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$PROJECT_ROOT/dist/mouNTFS-$VERSION-dev-$(uname -m).zip"
