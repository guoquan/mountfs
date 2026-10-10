#!/bin/bash
# Queries only IOKit metadata for a CI disk. Never opens a raw device.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELPER="$ROOT/dist/mouNTFS.app/Contents/MacOS/mountfs-identity"
"$HELPER" --authorization-self-test
SERVICE="$ROOT/dist/mouNTFS.app/Contents/MacOS/mountfs-helper"
"$SERVICE" --self-test
CLIENT_REQUIREMENT=$(/usr/libexec/PlistBuddy -c 'Print :client' "$ROOT/dist/mouNTFS.app/Contents/Resources/HelperPeers.plist")
SERVER_REQUIREMENT=$(/usr/libexec/PlistBuddy -c 'Print :server' "$ROOT/dist/mouNTFS.app/Contents/Resources/HelperPeers.plist")
/usr/bin/codesign --verify --strict -R "=$CLIENT_REQUIREMENT" "$HELPER"
/usr/bin/codesign --verify --strict -R "=$SERVER_REQUIREMENT" "$SERVICE"
if /usr/bin/codesign --verify --strict -R "=$CLIENT_REQUIREMENT" "$ROOT/dist/mouNTFS.app/Contents/MacOS/mouNTFS" 2>/dev/null; then exit 1; fi
/usr/bin/codesign -d --verbose=4 "$HELPER" 2>&1 | grep -q 'flags=.*runtime'
printf 'PASS exact client/server signing pins reject an unrelated bundled executable\n'
if "$HELPER" --identity 'disk0s1;touch bad' >/dev/null 2>&1; then exit 1; fi
if "$HELPER" --identity disk99999s1 >/dev/null 2>&1; then exit 1; fi
listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
/usr/sbin/diskutil list -plist > "$listing"
# Exercise the real kernel mount table against a mounted CI filesystem.
/usr/sbin/diskutil info -plist /System/Volumes/Data > "$listing"
mounted_device=$(/usr/libexec/PlistBuddy -c 'Print :DeviceIdentifier' "$listing")
expected_point=$(/usr/libexec/PlistBuddy -c 'Print :MountPoint' "$listing")
"$HELPER" --mount-state "$mounted_device" > "$listing"
[ "$(/usr/libexec/PlistBuddy -c 'Print :MountPoint' "$listing")" = "$expected_point" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :MountSource' "$listing")" = "/dev/$mounted_device" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :WritableVolume' "$listing")" = true ]
"$HELPER" --mount-state disk99999s1 > "$listing"
[ -z "$(/usr/libexec/PlistBuddy -c 'Print :MountPoint' "$listing")" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :WritableVolume' "$listing")" = false ]
if "$HELPER" --mount-state 'disk0s1;touch bad' >/dev/null 2>&1; then exit 1; fi
printf 'PASS actual kernel mount source/path/flags and missing mount rejection\n'
/usr/sbin/diskutil list -plist > "$listing"
index=0
while device=$(/usr/libexec/PlistBuddy -c "Print :AllDisks:$index" "$listing" 2>/dev/null); do
    index=$((index + 1))
    if value=$("$HELPER" --identity "$device" 2>/dev/null); then
        [[ "$value" =~ ^iomedia:[0-9]+:[0-9]+:[0-9]+$ ]] || exit 1
        [ "$("$HELPER" --identity "$device")" = "$value" ]
        printf 'PASS actual IOMedia lookup stable across repeated metadata queries\n'
        exit 0
    fi
done
printf 'No IOMedia partition could be queried on this CI Mac.\n' >&2
exit 1
