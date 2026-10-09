#!/bin/bash
# Deterministic disk-operation simulations. Never calls sudo or touches a device.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
passed=0

run_case() (
    set +e
    . "$ROOT/mountfs.sh"
    TEST_DIR="$FIXTURE/$1"
    mkdir -p "$TEST_DIR"
    printf 'mounted\n' > "$TEST_DIR/state"
    : > "$TEST_DIR/calls"
    DEVICE=disk4s1
    VOLUME_UUID=ABC-123
    VOLUME_NAME="Bill's disk \$(touch should-not-exist)"
    MOUNTED=true
    MOUNT_POINT="/Volumes/Bill's disk"
    READ_ONLY=true
    USER_ID=501
    GROUP_ID=20
    DRIVER=/opt/homebrew/bin/ntfs-3g
    GUI=1
    scenario="$1"
    acquire_lock() { return 0; }
    confirm_mount() { [ "$scenario" != cancel ]; }
    sleep() { :; }
    load_volume() {
        if [ "$scenario" = unplug ] && [ -f "$TEST_DIR/unmounted" ]; then return 1; fi
        DEVICE=disk4s1
        VOLUME_UUID=ABC-123
        if [ "$scenario" = replaced ] && [ -f "$TEST_DIR/unmounted" ]; then VOLUME_UUID=OTHER; fi
        MOUNTED=false; MOUNT_POINT=; READ_ONLY=true
        case "$(cat "$TEST_DIR/state")" in
            mounted) MOUNTED=true; MOUNT_POINT="/Volumes/Bill's disk" ;;
            driver-mounted) MOUNTED=true; MOUNT_POINT=/Volumes/mountfs.disk4s1.ABC123; READ_ONLY=false ;;
            readonly) MOUNTED=true; MOUNT_POINT=/Volumes/mountfs.disk4s1.ABC123 ;;
        esac
    }
    run_privileged() {
        printf '%s\n' "$*" >> "$TEST_DIR/calls"
        case "$1" in
            /usr/bin/mktemp) printf '/Volumes/mountfs.disk4s1.ABC123\n' ;;
            /usr/sbin/diskutil)
                if [ "$2" = unmount ]; then
                    [ "$scenario" != busy ] || return 1
                    printf 'unmounted\n' > "$TEST_DIR/state"
                    touch "$TEST_DIR/unmounted"
                elif [ "$2" = mount ]; then
                    [ "$3" = readOnly ] || return 1
                    printf 'restored\n' > "$TEST_DIR/state"
                fi ;;
            /opt/homebrew/bin/ntfs-3g)
                [ "$2" = /dev/disk4s1 ] || return 1
                [ "$3" = /Volumes/mountfs.disk4s1.ABC123 ] || return 1
                [ "$4" = -o ] || return 1
                case "$5" in *force*|*remove_hiberfile*) return 99 ;; esac
                case "$scenario" in
                    driver-failure) return 1 ;;
                    readonly-success) printf 'readonly\n' > "$TEST_DIR/state" ;;
                    *) printf 'driver-mounted\n' > "$TEST_DIR/state" ;;
                esac ;;
        esac
    }
    # The transaction tests simulate write verification. The separate probe test
    # below exercises actual exclusive file creation and cleanup.
    verify_write() {
        same_volume "$1" "$2" && [ "$MOUNTED" = true ] &&
            [ "$MOUNT_POINT" = "$3" ] && [ "$READ_ONLY" = false ] &&
            [ "$scenario" != probe-failure ]
    }
    mount_volume >/dev/null 2>&1
    result=$?
    if [ "$RECOVERY_NEEDED" -eq 1 ]; then recover_volume "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" >/dev/null 2>&1; fi
    case "$scenario" in
        success) [ "$result" -eq 0 ] && [ "$RECOVERY_NEEDED" -eq 0 ] && [ "$(cat "$TEST_DIR/state")" = driver-mounted ] ;;
        cancel) [ "$result" -eq 2 ] && [ ! -s "$TEST_DIR/calls" ] ;;
        busy) [ "$result" -eq 1 ] && [ "$(cat "$TEST_DIR/state")" = mounted ] && ! grep -q '/opt/homebrew/bin/ntfs-3g' "$TEST_DIR/calls" ;;
        driver-failure|readonly-success|probe-failure)
            [ "$result" -eq 1 ] && [ "$(cat "$TEST_DIR/state")" = restored ] && grep -q 'mount readOnly disk4s1' "$TEST_DIR/calls" ;;
        unplug|replaced)
            [ "$result" -eq 1 ] && ! grep -q 'mount readOnly' "$TEST_DIR/calls" && ! grep -q '/opt/homebrew/bin/ntfs-3g' "$TEST_DIR/calls" ;;
    esac
)

for scenario in success cancel busy driver-failure readonly-success probe-failure unplug replaced; do
    if run_case "$scenario"; then
        printf 'PASS %s\n' "$scenario"
        passed=$((passed + 1))
    else
        printf 'FAIL %s\n' "$scenario" >&2
        exit 1
    fi
done

(
    . "$ROOT/mountfs.sh"
    point="$FIXTURE/probe with spaces and 'quotes'"
    mkdir -p "$point"
    printf 'user data\n' > "$point/.write_test"
    same_volume() { MOUNTED=true; MOUNT_POINT="$point"; READ_ONLY=false; }
    verify_write disk4s1 ABC-123 "$point"
    [ "$(cat "$point/.write_test")" = 'user data' ]
    [ "$(find "$point" -name '.mountfs-write-test.*' | wc -l | tr -d ' ')" = 0 ]
)
printf 'PASS exclusive write probe preserves existing files\n'
passed=$((passed + 1))

# Exercise structured metadata validation without relying on a real disk.
(
    . "$ROOT/mountfs.sh"
    SESSION_DIR="$FIXTURE"
    ntfs_boot_identity() { return 1; }
    diskutil_cmd() { :; }
    kind=ntfs; is_internal=false; identity=ABC-123; partition_identity=; identifier=disk4s1
    plist_value() {
        case "$2" in
            DeviceIdentifier) printf '%s\n' "$identifier" ;;
            FilesystemType) printf '%s\n' "$kind" ;;
            WholeDisk) printf 'false\n' ;;
            Internal) printf '%s\n' "$is_internal" ;;
            DiskUUID) [ -n "$partition_identity" ] && printf '%s\n' "$partition_identity" ;;
            VolumeUUID) [ -n "$identity" ] && printf '%s\n' "$identity" ;;
            VolumeName) printf "Bill's disk\n" ;;
            MountPoint) printf "/Volumes/Bill's disk\n" ;;
            WritableVolume) printf 'false\n' ;;
        esac
    }
    load_volume disk4s1
    [ "$VOLUME_NAME" = "Bill's disk" ]
    kind=apfs
    if load_volume disk4s1 2>/dev/null; then exit 1; fi
    kind=ntfs; is_internal=true
    if load_volume disk4s1 2>/dev/null; then exit 1; fi
    is_internal=false; identity=
    if load_volume disk4s1 2>/dev/null; then exit 1; fi
    partition_identity=GPT-456
    load_volume disk4s1
    [ "$VOLUME_UUID" = partition:GPT-456 ]
    same_volume disk4s1 partition:GPT-456
    partition_identity=REPLACEMENT
    if same_volume disk4s1 partition:GPT-456; then exit 1; fi
    partition_identity=
    identity=ABC-123; identifier='disk4s1;touch bad'
    if load_volume disk4s1 2>/dev/null; then exit 1; fi
    identifier=disk4s1; kind=fusefs
    same_volume disk4s1 volume:ABC-123
    if same_volume disk4s1 DIFFERENT; then exit 1; fi
)
printf 'PASS metadata, external-disk and identity validation\n'
passed=$((passed + 1))
printf '%s regression groups passed.\n' "$passed"
