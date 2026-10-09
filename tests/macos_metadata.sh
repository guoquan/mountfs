#!/bin/bash
# Read-only tests of real diskutil output and PlistBuddy behavior on the CI Mac.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/mountfs.sh"
SESSION_DIR=$(mktemp -d)
trap 'rm -rf "$SESSION_DIR"' EXIT
/usr/sbin/diskutil info -plist / > "$SESSION_DIR/root.plist"
actual="$SESSION_DIR/root.plist"
[ "$(plist_value "$actual" WholeDisk)" = false ]
case "$(plist_value "$actual" WritableVolume)" in true|false) ;; *) exit 1 ;; esac
load_mount_state "$actual"
[ "$MOUNTED" = true ]
[ "$MOUNT_POINT" = / ]
printf 'PASS real diskutil root metadata and mounted-state parsing\n'

# NTFS fixture uses the actual plist keys, passed through the actual PlistBuddy.
cat > "$SESSION_DIR/ntfs.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>DeviceIdentifier</key><string>disk4s1</string>
<key>FilesystemType</key><string>ntfs</string>
<key>WholeDisk</key><false/>
<key>Internal</key><false/>
<key>VolumeUUID</key><string>ABC-123</string>
<key>VolumeName</key><string>USB</string>
<key>MountPoint</key><string>/Volumes/USB</string>
<key>WritableVolume</key><false/>
</dict></plist>
PLIST
diskutil_cmd() { cat "$SESSION_DIR/ntfs.plist"; }
load_volume disk4s1
[ "$MOUNTED" = true ] && [ "$READ_ONLY" = true ]
/usr/libexec/PlistBuddy -c 'Set :MountPoint ""' "$SESSION_DIR/ntfs.plist"
load_volume disk4s1
[ "$MOUNTED" = false ] && [ -z "$MOUNT_POINT" ]
/usr/libexec/PlistBuddy -c 'Set :MountPoint /Volumes/USB' "$SESSION_DIR/ntfs.plist"
/usr/libexec/PlistBuddy -c 'Set :WritableVolume true' "$SESSION_DIR/ntfs.plist"
load_volume disk4s1
[ "$MOUNTED" = true ] && [ "$READ_ONLY" = false ]
printf 'PASS actual PlistBuddy NTFS state parsing\n'
