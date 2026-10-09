#!/bin/bash
# Queries only IOKit metadata for a CI disk. Never opens a raw device.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELPER="$ROOT/dist/mouNTFS-$(bash "$ROOT/mountfs.sh" --version).app/Contents/MacOS/mountfs-identity"
if "$HELPER" --identity 'disk0s1;touch bad' >/dev/null 2>&1; then exit 1; fi
if "$HELPER" --identity disk99999s1 >/dev/null 2>&1; then exit 1; fi
listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
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
