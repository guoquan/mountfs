#!/bin/bash
# Connection-scoped identity simulations. No disk is opened or modified.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/mountfs.sh"
SESSION_DIR=$(mktemp -d)
trap 'rm -rf "$SESSION_DIR"' EXIT
DEVICE=disk4s1
identity=iomedia:100:50:1048576
uuid=
media_identity_command() { printf '%s\n' "$identity"; }
ntfs_boot_identity() { printf 'Unexpected raw read\n' >&2; return 99; }
diskutil_cmd() { :; }
plist_value() {
    case "$2" in
        DeviceIdentifier) printf 'disk4s1\n' ;;
        FilesystemType) printf 'ntfs\n' ;;
        WholeDisk|Internal|WritableVolume) printf 'false\n' ;;
        DiskUUID|VolumeUUID) [ -n "$uuid" ] && printf '%s\n' "$uuid" ;;
        *) return 1 ;;
    esac
}
load_volume disk4s1
[ "$VOLUME_UUID" = "$identity" ]
same_volume disk4s1 "$identity"
printf 'PASS UUID-less registry identity without raw-device reads\n'
uuid=NEWLY-VISIBLE-UUID
same_volume disk4s1 "$identity"
printf 'PASS registry source pinned across driver metadata changes\n'
expected="$identity"
identity=iomedia:101:51:1048576
if same_volume disk4s1 "$expected"; then exit 1; fi
identity=iomedia:100:50:1048576
# Same device number and size, but a new parent media connection.
identity=iomedia:100:51:1048576
if same_volume disk4s1 "$expected"; then exit 1; fi
printf 'PASS replacement and changed parent refused\n'
identity='iomedia:100:50:1048576;touch bad'
if media_identity; then exit 1; fi
media_identity_command() { return 1; }
if same_volume disk4s1 "$expected" 2>/dev/null; then exit 1; fi
printf 'PASS invalid/missing registry identity fails closed\n'
# The native menu's captured identity must survive into main, not be repinned to
# whichever disk happens to occupy this identifier when the shell starts.
(
    . "$ROOT/mountfs.sh"
    uname() { printf 'Darwin\n'; }
    id() { case "$1" in -u) printf '501\n';; -g) printf '20\n';; esac; }
    find_driver() { return 0; }
    check_backend() { return 0; }
    load_volume() {
        [ "$3" = iomedia:100:50:1048576 ] || exit 90
        VOLUME_UUID=iomedia:101:51:1048576
    }
    mount_volume() { printf 'MUTATION MUST NOT RUN\n'; exit 91; }
    if main --app-action --device disk4s1 --expected-identity iomedia:100:50:1048576; then exit 1; fi
    cleanup
)
printf 'PASS stale menu identity rejected before mount transaction starts\n'
