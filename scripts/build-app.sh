#!/bin/bash
set -euo pipefail
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT"
if [ "$(uname -s)" != Darwin ]; then
    printf 'The menu bar app must be built on macOS with Xcode command line tools.\n' >&2
    exit 1
fi
SIGNING_IDENTITY=${MOUNTFS_SIGNING_IDENTITY:--}
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
VERSION=$(bash mountfs.sh --version)
APP="$PROJECT_ROOT/dist/mouNTFS.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MountFS" "$APP/Contents/MacOS/mouNTFS"
cp "$BIN_DIR/MountFSIdentity" "$APP/Contents/MacOS/mountfs-identity"
# Pin the live XPC client to this exact hardened binary, including ad-hoc builds.
/usr/bin/codesign --force --options runtime --identifier net.guoquan.mountfs.client --sign "$SIGNING_IDENTITY" "$APP/Contents/MacOS/mountfs-identity"
CLIENT_HASH=$(/usr/bin/codesign -d --verbose=4 "$APP/Contents/MacOS/mountfs-identity" 2>&1 | sed -n 's/^CDHash=//p')
[[ "$CLIENT_HASH" =~ ^[0-9a-f]{40}$ ]] || { printf 'Cannot pin helper client signature.\n' >&2; exit 1; }
cp mountfs.sh "$APP/Contents/Resources/mountfs.sh"
ICON_WORK=$(mktemp -d "${TMPDIR:-/tmp}/mountfs-icons.XXXXXXXX")
cp Sources/MountFSHelper/ClientIdentity.swift "$ICON_WORK/ClientIdentity.swift"
cleanup_build() {
    cp "$ICON_WORK/ClientIdentity.swift" Sources/MountFSHelper/ClientIdentity.swift
    rm -rf "$ICON_WORK"
}
trap cleanup_build EXIT
printf 'let allowedHelperClient = #"cdhash H"%s""#\n' "$CLIENT_HASH" > Sources/MountFSHelper/ClientIdentity.swift
swift build -c release --product MountFSHelper
cp "$BIN_DIR/MountFSHelper" "$APP/Contents/MacOS/mountfs-helper"
/usr/bin/codesign --force --options runtime --identifier net.guoquan.mountfs.helper --sign "$SIGNING_IDENTITY" "$APP/Contents/MacOS/mountfs-helper"
SERVER_HASH=$(/usr/bin/codesign -d --verbose=4 "$APP/Contents/MacOS/mountfs-helper" 2>&1 | sed -n 's/^CDHash=//p')
[[ "$SERVER_HASH" =~ ^[0-9a-f]{40}$ ]] || { printf 'Cannot pin service signature.\n' >&2; exit 1; }
/usr/bin/plutil -create xml1 "$APP/Contents/Resources/HelperPeers.plist"
/usr/bin/plutil -insert server -string "cdhash H\"$SERVER_HASH\"" "$APP/Contents/Resources/HelperPeers.plist"
/usr/bin/plutil -insert client -string "cdhash H\"$CLIENT_HASH\"" "$APP/Contents/Resources/HelperPeers.plist"
mkdir -p "$APP/Contents/Library/LaunchDaemons"
# Bind launchd's spawn constraint to the final signed helper, before sealing
# the app. CDHash is plist Data (20 bytes), not its hexadecimal text spelling.
python3 - scripts/net.guoquan.mountfs.helper.plist "$APP/Contents/Library/LaunchDaemons/net.guoquan.mountfs.helper.plist" "$SERVER_HASH" <<'PYCONSTRAINT'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    service = plistlib.load(source)
service['SpawnConstraint'] = {
    'signing-identifier': 'net.guoquan.mountfs.helper',
    'cdhash': bytes.fromhex(sys.argv[3]),
}
with open(sys.argv[2], 'wb') as output:
    plistlib.dump(service, output)
PYCONSTRAINT
swiftc Sources/MountFSApp/BrandIcon.swift scripts/generate-icons.swift -o "$ICON_WORK/generate-icons"
"$ICON_WORK/generate-icons" "$ICON_WORK/AppIcon.iconset"
/usr/bin/iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp scripts/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signing is for local development only. Public distribution requires
# a Developer ID signature and Apple notarization.
/usr/bin/codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP"
if [ "$SIGNING_IDENTITY" = - ]; then
    printf 'Warning: ad-hoc signing is not a reliable SMAppService registration identity. Use MOUNTFS_SIGNING_IDENTITY with an Apple-issued certificate for helper testing.\n' >&2
fi
printf 'Built development app: %s\n' "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$PROJECT_ROOT/dist/mouNTFS-$VERSION-dev-$(uname -m).zip"
