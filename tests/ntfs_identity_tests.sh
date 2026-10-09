#!/bin/bash
# All raw reads and authorization are mocked; no physical device is opened.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/mountfs.sh"
    media_identity_command() { return 1; }
DEVICE=disk4s1
zeroes=$(printf '%01024d' 0)
# Boot sector with NTFS OEM, 512 byte sectors, one sector per cluster,
# nonzero geometry/serial and 55aa trailer. Entire record is fingerprinted.
valid="${zeroes:0:6}4e54465320202020000201${zeroes:28:52}0100000000000000${zeroes:96:48}0123456789abcdef${zeroes:160:860}55aa"
[ "${#valid}" -eq 1024 ]
fixture="$valid"
raw_read_command() {
    [ "$1" = /dev/rdisk4s1 ] || return 1
    printf '%s\n' "$fixture"
}
run_privileged() { printf 'Unexpected authorization\n' >&2; return 99; }
original=$(ntfs_boot_identity)
case "$original" in ntfs-boot:*) ;; *) exit 1 ;; esac
[ "${#original}" -eq 74 ]
plist_value() { return 1; }
[ "$(volume_identity ignored)" = "$original" ]
printf 'PASS UUID-less NTFS identity from boot record\n'
# Keep boot identity when mounting causes UUID metadata to appear.
plist_value() { printf 'NEW-UUID\n'; }
[ "$(volume_identity ignored "$original")" = "$original" ]
fixture="${valid:0:144}fedcba9876543210${valid:160}"
[ "$(ntfs_boot_identity)" != "$original" ]
printf 'PASS pinned boot identity and replacement fingerprint\n'
for fixture in "${valid:0:6}0000000000000000${valid:22}" \
    "${valid:0:144}0000000000000000${valid:160}" \
    "${valid:0:1020}0000" "${valid:0:1000}" \
    "${valid:0:22}0000${valid:26}" "${valid:0:80}0000000000000000${valid:96}"; do
    if ntfs_boot_identity >/dev/null 2>&1; then exit 1; fi
done
fixture="$valid"
DEVICE='disk4s1;touch bad'
if ntfs_boot_identity >/dev/null 2>&1; then exit 1; fi
DEVICE=disk4s1
printf 'PASS invalid, truncated and unsafe device inputs rejected\n'
raw_read_command() { return 1; }
run_privileged() {
    [ "$1" = /bin/bash ] && [ "$2" = -o ] && [ "$3" = pipefail ] &&
        [ "$4" = -c ] && [ "$5" = "$BOOT_READ_SCRIPT" ] &&
        [ "$6" = mountfs-read ] && [ "$7" = /dev/rdisk4s1 ] || return 99
    printf '%s\n' "$fixture"
}
[ "$(ntfs_boot_identity)" = "$original" ]
run_privileged() { return 1; }
if ntfs_boot_identity >/dev/null 2>&1; then exit 1; fi
printf 'PASS read-only authorization fallback and refusal\n'
# Real transaction checks with boot identity. Mock only disk metadata/commands.
plist_value() {
    case "$2" in
        DeviceIdentifier) printf 'disk4s1\n' ;;
        FilesystemType) printf 'ntfs\n' ;;
        WholeDisk|Internal|WritableVolume) printf 'false\n' ;;
        *) return 1 ;;
    esac
}
SESSION_DIR=$(mktemp -d)
trap 'rm -rf "$SESSION_DIR"' EXIT
diskutil_cmd() { :; }
# Invoked indirectly by same_volume -> load_volume -> boot identity.
# shellcheck disable=SC2317
raw_read_command() { printf '%s\n' "$fixture"; }
same_volume disk4s1 "$original"
fixture="${valid:0:144}fedcba9876543210${valid:160}"
if same_volume disk4s1 "$original"; then exit 1; fi
printf 'PASS same_volume rejects UUID-less replacement device\n'

# Exercise the real dd/od pipeline on a regular fixture, including pipefail.
# No physical device is opened. Also catches macOS/GNU utility differences.
(
    reader_fixture_dir="$SESSION_DIR"
    . "$ROOT/mountfs.sh"
    fixture_file="$reader_fixture_dir/boot.bin"
    /usr/bin/perl -e 'print pack("H*", $ARGV[0])' "$valid" > "$fixture_file"
    aligned=$(raw_read_command "$fixture_file" 2>/dev/null | tr -d '[:space:]')
    [ "$aligned" = "$valid" ]
    if raw_read_command "$reader_fixture_dir/missing" >/dev/null 2>&1; then exit 1; fi
)
fixture="$valid$(printf '%07168d' 0)"
raw_read_command() { printf '%s\n' "$fixture" | tr 'a-f' 'A-F'; }
[ "$(ntfs_boot_identity)" = "$original" ]
printf 'PASS actual aligned dd/od reader, full-block normalization and pipeline failure propagation\n'
