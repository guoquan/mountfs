#!/bin/bash
# Mount-state authority and verification guards; no real disks or privileges.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
. "$ROOT/mountfs.sh"
SESSION_DIR="$fixture"
DEVICE=disk6s1
USER_ID=501
GROUP_ID=20
native_status=0
native_point="$fixture/volume with spaces"
native_writable=true
mkdir "$native_point"
# shellcheck disable=SC2317
native_helper_command() { printf 'kernel\n'; return "$native_status"; }
# shellcheck disable=SC2317
plist_value() {
    case "$1:$2" in
        *mount-state.plist:MountPoint) printf '%s\n' "$native_point" ;;
        *mount-state.plist:WritableVolume) printf '%s\n' "$native_writable" ;;
        *:MountPoint) printf '/Volumes/incorrect-diskutil-path\n' ;;
        *:WritableVolume) printf 'false\n' ;;
        *) return 1 ;;
    esac
}
load_mount_state "$fixture/diskutil.plist"
[ "$MOUNT_POINT" = "$native_point" ] && [ "$READ_ONLY" = false ]
# shellcheck disable=SC2317
same_volume() { load_mount_state "$fixture/diskutil.plist"; }
verify_write disk6s1 identity "$native_point"
[ -z "$(ls -A "$native_point")" ]
printf 'PASS native mount table overrides stale diskutil metadata and probe is removed\n'
native_writable=false
if verify_write disk6s1 identity "$native_point" 2>/dev/null; then exit 1; fi
native_writable=true
if verify_write disk6s1 identity "$fixture/wrong" 2>/dev/null; then exit 1; fi
native_point=
if verify_write disk6s1 identity "$fixture" 2>/dev/null; then exit 1; fi
[ ! -e "$fixture/.mountfs-write-test" ]
printf 'PASS read-only, wrong-path and absent mounts rejected before probing\n'
native_status=1
if load_mount_state "$fixture/diskutil.plist" 2>/dev/null; then exit 1; fi
native_status=127
load_mount_state "$fixture/diskutil.plist"
[ "$MOUNT_POINT" = /Volumes/incorrect-diskutil-path ] && [ "$READ_ONLY" = true ]
printf 'PASS native query failure is closed; only missing helper allows standalone fallback\n'
