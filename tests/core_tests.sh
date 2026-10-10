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
    SESSION_DIR="$TEST_DIR"
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
    case "$scenario" in
        helper-success|helper-commit-failure|helper-commit-uncertain)
            AUTH_PRIVILEGED=1
            AUTH_HELPER=fake_commit
            AUTH_SESSION_PID=123
            # Called indirectly through AUTH_HELPER.
            # shellcheck disable=SC2317
            fake_commit() {
                [ "$1" = --authorization-request ] && [ "$4" = --helper-commit ] || return 1
                [ "$(cat "$TEST_DIR/state")" = driver-mounted ] || return 1
                printf 'commit\n' >> "$TEST_DIR/calls"
                [ "$scenario" != helper-commit-uncertain ] || return 125
                [ "$scenario" != helper-commit-failure ]
            } ;;
    esac
    acquire_lock() { return 0; }
    start_authorization_session() { return 0; }
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
            --helper-commit) request_authorized "$@" ;;
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
                    driver-unconfirmed) return 125 ;;
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
    if [ "$scenario" = driver-unconfirmed ] || [ "$scenario" = helper-commit-uncertain ]; then
        LOCK_DIR=retained-token
        SESSION_DIR=
        AUTH_SESSION_PID=
        cleanup >/dev/null 2>&1
        [ "$?" -eq 125 ] || exit 1
    elif [ "$RECOVERY_NEEDED" -eq 1 ]; then recover_volume "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" >/dev/null 2>&1; fi
    case "$scenario" in
        success|helper-success) [ "$result" -eq 0 ] && [ "$RECOVERY_NEEDED" -eq 0 ] && [ "$(cat "$TEST_DIR/state")" = driver-mounted ] ;;
        driver-unconfirmed|helper-commit-uncertain) [ "$result" -eq 125 ] && [ "$DRIVER_TERMINATION_UNCONFIRMED" -eq 1 ] && [ "$LOCK_DIR" = retained-token ] && ! grep -Eq "mount readOnly|rmdir|system-device-lock release" "$TEST_DIR/calls" ;;
        cancel) [ "$result" -eq 2 ] && [ ! -s "$TEST_DIR/calls" ] ;;
        busy) [ "$result" -eq 1 ] && [ "$(cat "$TEST_DIR/state")" = mounted ] && ! grep -q '/opt/homebrew/bin/ntfs-3g' "$TEST_DIR/calls" ;;
        driver-failure|readonly-success|probe-failure|helper-commit-failure)
            [ "$result" -eq 1 ] && [ "$(cat "$TEST_DIR/state")" = restored ] && grep -q 'mount readOnly disk4s1' "$TEST_DIR/calls" ;;
        unplug|replaced)
            [ "$result" -eq 1 ] && ! grep -q 'mount readOnly' "$TEST_DIR/calls" && ! grep -q '/opt/homebrew/bin/ntfs-3g' "$TEST_DIR/calls" ;;
    esac
)

for scenario in success helper-success helper-commit-failure helper-commit-uncertain cancel busy driver-failure driver-unconfirmed readonly-success probe-failure unplug replaced; do
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
    media_identity_command() { return 1; }
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
(
    . "$ROOT/mountfs.sh"
    # App menu action replaces only its own redundant GUI confirmation.
    APP_ACTION=1
    GUI=1
    confirm_mount
    if main --app-action --device disk4s1 >/dev/null 2>&1; then exit 1; fi
    if main --app-action --expected-identity bad --device disk4s1 >/dev/null 2>&1; then exit 1; fi
    if main --app-action --cli --device disk4s1 >/dev/null 2>&1; then exit 1; fi
    if main --app-action >/dev/null 2>&1; then exit 1; fi
)
printf 'PASS app action requires explicit GUI device and does not prompt twice\n'
passed=$((passed + 1))
(
    . "$ROOT/mountfs.sh"
    log="$FIXTURE/driver.log"
    printf 'Error opening device: Operation not permitted\nNTFS partition is in an unsafe state.\n' > "$log"
    output=$(report_driver_failure "$log" 2>&1) && exit 1
    case "$output" in *"Allow the actual ntfs-3g executable"*) ;; *) exit 1 ;; esac
    printf 'Permission denied\n' > "$log"
    output=$(report_driver_failure "$log" 2>&1) && exit 1
    case "$output" in *"Allow the actual ntfs-3g executable"*) ;; *) exit 1 ;; esac
    printf 'mount_macfuse: the file system is not available\n' > "$log"
    output=$(report_driver_failure "$log" 2>&1) && exit 1
    case "$output" in *"macFUSE could not load"*) ;; *) exit 1 ;; esac
    printf 'The partition is hibernated\n' > "$log"
    output=$(report_driver_failure "$log" 2>&1) && exit 1
    case "$output" in *"unsafe NTFS state"*) ;; *) exit 1 ;; esac
    printf 'Other driver error\n' > "$log"
    output=$(report_driver_failure "$log" 2>&1) && exit 1
    case "$output" in *"Open Show Details for the driver error"*) ;; *) exit 1 ;; esac
)
printf 'PASS concrete permission errors take priority over generic unsafe-state hints\n'
passed=$((passed + 1))
(
    . "$ROOT/mountfs.sh"
    GUI=1
    AUTH_SESSION_PID=123
    AUTH_HELPER=fake_authorization_host
    # shellcheck disable=SC2317
    fake_authorization_host() {
        [ "$1" = --authorization-request ] && [ "$3" = 123 ] &&
            [ "$4" = /usr/sbin/diskutil ] && [ "$5" = unmount ] && [ "$6" = disk6s1 ]
    }
    osascript_cmd() { return 99; }
    run_privileged /usr/sbin/diskutil unmount disk6s1
)
printf 'PASS privileged requests reuse the existing host instead of starting osascript\n'
passed=$((passed + 1))
for completion in release acknowledge; do
    (
        . "$ROOT/mountfs.sh"
        completion_log="$FIXTURE/cleanup-$completion"
        native_helper_path() { printf '/test/native-helper'; }
        run_privileged() {
            printf '%s\n' "$*" >> "$completion_log"
            DRIVER_TERMINATION_UNCONFIRMED=1
            return 125
        }
        if [ "$completion" = release ]; then
            LOCK_DIR=test-token
            TRANSACTION_DEVICE=disk4s1
        else
            AUTH_PRIVILEGED=1
            HELPER_COMMIT_CONFIRMED=1
        fi
        if cleanup 2> "$completion_log.error"; then exit 1; else result=$?; fi
        [ "$result" -eq 125 ]
        [ "$(wc -l < "$completion_log" | tr -d ' ')" = 1 ]
        grep -q 'device-lock state are uncertain' "$completion_log.error"
    )
    printf 'PASS uncertain cleanup %s preserves status 125\n' "$completion"
    passed=$((passed + 1))
done
(
    . "$ROOT/mountfs.sh"
    LOCK_DIR=test-token
    native_helper_path() { return 1; }
    run_privileged() { return 99; }
    if cleanup 2> "$FIXTURE/missing-cleanup-tool.error"; then exit 1; else result=$?; fi
    [ "$result" -eq 1 ]
    [ "$LOCK_DIR" = test-token ]
    grep -q 'identity tool is unavailable; the system device lock was retained' "$FIXTURE/missing-cleanup-tool.error"
)
printf 'PASS missing cleanup native tool reports failure and retains lock\n'
passed=$((passed + 1))
printf '%s regression groups passed.\n' "$passed"
