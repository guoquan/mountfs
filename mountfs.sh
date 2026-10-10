#!/bin/bash
# mouNTFS — MIT License, Copyright (c) 2024-2026 Quan Guo.
# See LICENSE for the full license text.
# Compatible with the Bash 3.2 shipped by macOS. No password is read by this script.

MOUNTFS_VERSION=0.3.3
GUI=1
APP_ACTION=0
AUTH_SESSION_PID=
AUTH_HELPER=
AUTH_PRIVILEGED=0
BACKEND=kernel
DRIVER=
SESSION_DIR=
LOCK_DIR=
DEVICE=
VOLUME_NAME=
MOUNT_POINT=
VOLUME_UUID=
MOUNTED=false
READ_ONLY=true
INTERNAL=true
NEW_MOUNT_POINT=
RECOVERY_NEEDED=0
USER_ID=
GROUP_ID=

diskutil_cmd() { /usr/sbin/diskutil "$@"; }
osascript_cmd() { /usr/bin/osascript "$@"; }

message() { printf '%s\n' "$*" >&2; }
fail() { message "Error: $*"; return 1; }

# Read structured disk metadata, never parse localized diskutil/df text.
plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

load_volume() {
    local target="$1" policy="${2:-ntfs}" expected_identity="${3:-}" info="$SESSION_DIR/info.plist" fs whole
    diskutil_cmd info -plist "$target" > "$info" || return 1
    DEVICE=$(plist_value "$info" DeviceIdentifier) || return 1
    case "$DEVICE" in
        disk[0-9]*s[0-9]*) ;;
        *) fail "Select an NTFS partition, not an entire disk."; return 1 ;;
    esac
    # Constrain the identifier before it is used in paths or privileged commands.
    [[ "$DEVICE" =~ ^disk[0-9]+s[0-9]+(s[0-9]+)?$ ]] || return 1
    if [ "$policy" = ntfs ]; then
        fs=$(plist_value "$info" FilesystemType) || return 1
        [ "$fs" = ntfs ] || { fail "Selected partition is not NTFS ($fs)."; return 1; }
    fi
    whole=$(plist_value "$info" WholeDisk) || return 1
    [ "$whole" = false ] || return 1
    INTERNAL=$(plist_value "$info" Internal) || return 1
    [ "$INTERNAL" = false ] || { fail "Internal disks are not supported in this release."; return 1; }
    # GPT partition UUID survives filesystem-driver changes. Never fall back to
    # a device number, volume name or mount path: those can match a replacement.
    VOLUME_UUID=$(volume_identity "$info" "$expected_identity") || return 1
    VOLUME_NAME=$(plist_value "$info" VolumeName) || VOLUME_NAME="$DEVICE"
    load_mount_state "$info"
}

# Raw devices can require sector-aligned reads. Read one 4096-byte block with
# dd, convert it to text with od, then inspect only the first 512 bytes. This
# fixed shell source has no interpolated device/name/path; the validated device
# is passed as $1. pipefail preserves a failed dd even when od exits successfully.
# $1 is expanded by the child Bash, never while constructing the command.
# shellcheck disable=SC2016
BOOT_READ_SCRIPT='/bin/dd if="$1" bs=4096 count=1 | /usr/bin/od -An -v -tx1'
raw_read_command() { /bin/bash -o pipefail -c "$BOOT_READ_SCRIPT" mountfs-read "$1"; }
read_ntfs_boot_hex() {
    local device="$1" raw hex
    [[ "$device" =~ ^disk[0-9]+s[0-9]+(s[0-9]+)?$ ]] || { fail "Invalid raw partition identifier."; return 1; }
    raw="/dev/r$device"
    hex=$(raw_read_command "$raw" 2>/dev/null) || {
        message "Reading the NTFS identity requires macOS authorization (read-only, one 4096-byte block)."
        hex=$(run_privileged /bin/bash -o pipefail -c "$BOOT_READ_SCRIPT" mountfs-read "$raw") || {
            fail "NTFS identity read failed for $device: macOS authorization or raw-device read failed. Show Details includes the macOS error; if access was denied, allow mouNTFS disk access and retry."
            return 1
        }
    }
    hex=$(printf '%s' "$hex" | tr -d '[:space:]' | tr 'A-F' 'a-f')
    if [ "${#hex}" -lt 1024 ] || [ "${#hex}" -gt 8192 ]; then
        fail "NTFS identity read returned an unexpected length (${#hex} hex characters; at least 1024 required)."
        return 1
    fi
    case "$hex" in *[!0-9a-f]*) fail "NTFS identity read returned invalid hex output."; return 1 ;; esac
    printf '%s\n' "${hex:0:1024}"
}

ntfs_boot_identity() {
    local hex serial digest
    hex=$(read_ntfs_boot_hex "$DEVICE") || return 1
    # NTFS OEM signature, sector trailer, supported sector and cluster sizes.
    # Layout: linux fs/ntfs3/ntfs.h struct NTFS_BOOT (serial at offset 0x48).
    [ "${hex:6:16}" = 4e54465320202020 ] || { fail "NTFS identity validation failed: missing NTFS OEM signature."; return 1; }
    [ "${hex:1020:4}" = 55aa ] || { fail "NTFS identity validation failed: missing boot-sector trailer."; return 1; }
    case "${hex:22:4}" in 0002|0004|0008|0010) ;; *) fail "NTFS identity validation failed: unsupported sector size."; return 1 ;; esac
    case "${hex:26:2}" in 01|02|04|08|10|20|40|80) ;; *) fail "NTFS identity validation failed: unsupported cluster size."; return 1 ;; esac
    serial=${hex:144:16}
    case "$serial" in 0000000000000000|ffffffffffffffff) fail "NTFS identity validation failed: empty or reserved volume serial."; return 1 ;; esac
    [ "${hex:80:16}" != 0000000000000000 ] || { fail "NTFS identity validation failed: empty volume geometry."; return 1; }
    # Fingerprint the entire boot record, including serial and geometry. Never
    # identify a drive using diskNsM, its label or its mount path alone.
    digest=$(printf '%s' "$hex" | /usr/bin/shasum -a 256) || return 1
    digest=${digest%% *}
    printf 'ntfs-boot:%s\n' "$digest"
}

# Bundled native helper queries the live IOMedia registry, without opening /dev.
# Its identity is valid only for this process/connection, never persisted.
native_helper_path() {
    local script_dir helper
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || return 1
    for helper in "$script_dir/../MacOS/mountfs-identity" "$script_dir/.build/release/MountFSIdentity"; do
        if [ -x "$helper" ]; then printf '%s\n' "$helper"; return 0; fi
    done
    return 127
}

native_helper_command() {
    local helper
    helper=$(native_helper_path) || return $?
    "$helper" "$@"
}

start_authorization_session() {
    [ "$GUI" -eq 1 ] || return 0
    AUTH_HELPER=$(native_helper_path) || return 0
    local mode=--authorization-session
    if [ "${MOUNTFS_PRIVILEGED_HELPER:-0}" = 1 ]; then
        mode=--privileged-session
        AUTH_PRIVILEGED=1
    fi
    "$AUTH_HELPER" "$mode" "$SESSION_DIR" "$DEVICE" "$DRIVER" "$USER_ID" "$GROUP_ID" "$$" \
        > "$SESSION_DIR/authorization-host.log" 2>&1 &
    AUTH_SESSION_PID=$!
}

media_identity_command() { native_helper_command --identity "$DEVICE"; }

media_identity() {
    local value
    value=$(media_identity_command) || return 1
    [[ "$value" =~ ^iomedia:[0-9]+:[0-9]+:[0-9]+$ ]] || return 1
    printf '%s\n' "$value"
}

volume_identity() {
    local info="$1" expected="${2:-}" value
    # Pin the chosen identity source throughout the transaction even if a FUSE
    # driver makes additional UUID metadata appear after mounting.
    case "$expected" in
        iomedia:*) media_identity || { fail "The connected media identity is unavailable; reconnect and retry. No alternate identity source was used."; return 1; }; return 0 ;;
        ntfs-boot:*) ntfs_boot_identity; return $? ;;
    esac
    value=$(plist_value "$info" DiskUUID) || value=
    if [ -n "$value" ]; then printf 'partition:%s\n' "$value"; return 0; fi
    value=$(plist_value "$info" VolumeUUID) || value=
    if [ -n "$value" ]; then printf 'volume:%s\n' "$value"; return 0; fi
    if media_identity; then return 0; fi
    ntfs_boot_identity
}

load_mount_state() {
    local info="$1" writable native="$SESSION_DIR/mount-state.plist" status
    if native_helper_command --mount-state "$DEVICE" > "$native"; then
        info="$native"
    else
        status=$?
        [ "$status" = 127 ] || { fail "Cannot read the kernel mount table for $DEVICE."; return 1; }
        # Standalone shell usage without the bundled helper retains diskutil.
    fi
    MOUNT_POINT=$(plist_value "$info" MountPoint) || MOUNT_POINT=
    # diskutil reports mounting through MountPoint, not a Mounted boolean.
    MOUNTED=false
    [ -z "$MOUNT_POINT" ] || MOUNTED=true
    READ_ONLY=true
    writable=$(plist_value "$info" WritableVolume) || writable=false
    [ "$writable" != true ] || READ_ONLY=false
}

find_driver() {
    local candidate
    for candidate in /opt/homebrew/bin/ntfs-3g /usr/local/bin/ntfs-3g; do
        if [ -x "$candidate" ] && [ ! -d "$candidate" ]; then
            DRIVER="$candidate"
            return 0
        fi
    done
    fail "ntfs-3g was not found. Install: brew install gromgit/fuse/ntfs-3g-mac"
}

check_backend() {
    local version major minor
    case "$BACKEND" in
        kernel) return 0 ;;
        fskit)
            version=$(/usr/bin/sw_vers -productVersion) || return 1
            major=${version%%.*}
            minor=${version#*.}; minor=${minor%%.*}
            if [ "$major" -lt 15 ] || { [ "$major" -eq 15 ] && [ "$minor" -lt 4 ]; }; then
                fail "FSKit requires macOS 15.4 or later."
                return 1
            fi
            message "FSKit is experimental in mouNTFS; this version combination requires real-disk validation."
            ;;
        *) fail "Unknown backend: $BACKEND"; return 1 ;;
    esac
}

# AppleScript source is constant. Every argument is shell-quoted by AppleScript.
# CLI uses sudo's own authentication. Neither mode handles the user's password.
run_privileged() {
    if [ "$GUI" -eq 0 ]; then
        /usr/bin/sudo -- "$@"
    elif [ -n "$AUTH_SESSION_PID" ]; then
        local auth_status=0
        "$AUTH_HELPER" --authorization-request "$SESSION_DIR" "$AUTH_SESSION_PID" "$@" || auth_status=$?
        if [ "$auth_status" -ne 0 ]; then cat "$SESSION_DIR/authorization-host.log" >&2; fi
        return "$auth_status"
    else
        osascript_cmd - "$@" <<'APPLESCRIPT'
on run argv
    set commandText to ""
    repeat with argument in argv
        set commandText to commandText & quoted form of (contents of argument) & " "
    end repeat
    return do shell script commandText with administrator privileges
end run
APPLESCRIPT
    fi
}

select_volume() {
    local listing="$SESSION_DIR/disks.plist" index=0 id info fs internal label selected
    local identifiers=() labels=()
    diskutil_cmd list -plist > "$listing" || return 1
    while id=$(plist_value "$listing" "AllDisks:$index"); do
        index=$((index + 1))
        info="$SESSION_DIR/candidate.plist"
        diskutil_cmd info -plist "$id" > "$info" 2>/dev/null || continue
        fs=$(plist_value "$info" FilesystemType) || continue
        internal=$(plist_value "$info" Internal) || continue
        if [ "$fs" != ntfs ] || [ "$internal" != false ]; then continue; fi
        label=$(plist_value "$info" VolumeName) || label="NTFS"
        identifiers[${#identifiers[@]}]="$id"
        labels[${#labels[@]}]="$id — $label"
    done
    [ "${#identifiers[@]}" -gt 0 ] || { fail "No external NTFS partitions found. Connect your drive and retry."; return 1; }
    if [ "$GUI" -eq 1 ]; then
        selected=$(osascript_cmd - "${labels[@]}" <<'APPLESCRIPT'
on run argv
    set selection to choose from list argv with title "mouNTFS" with prompt "Select an external NTFS volume:" OK button name "Continue" cancel button name "Cancel"
    if selection is false then return ""
    return item 1 of selection
end run
APPLESCRIPT
        ) || return 1
        [ -n "$selected" ] || return 2
        for ((index=0; index<${#labels[@]}; index++)); do
            if [ "$selected" = "${labels[$index]}" ]; then
                printf '%s\n' "${identifiers[$index]}"
                return 0
            fi
        done
        return 1
    fi
    for ((index=0; index<${#labels[@]}; index++)); do
        printf '%s\n' "${labels[$index]}"
    done
}

confirm_mount() {
    local response
    # The app's explicit per-volume menu action already expresses confirmation.
    # Standalone GUI/CLI invocations retain their confirmation prompt.
    if [ "$APP_ACTION" -eq 1 ] && [ "$GUI" -eq 1 ]; then return 0; fi
    if [ "$GUI" -eq 1 ]; then
        osascript_cmd - "$VOLUME_NAME" "$DEVICE" "$BACKEND" <<'APPLESCRIPT'
on run argv
    display dialog "Volume: " & item 1 of argv & "\nDevice: " & item 2 of argv & "\nBackend: " & item 3 of argv & "\n\nClose files on this drive before continuing. mouNTFS will unmount and remount it, then create and remove a private test file. Hibernated or unclean volumes will not be forced writable." with title "mouNTFS" buttons {"Cancel", "Enable Write Access"} default button "Enable Write Access" cancel button "Cancel" with icon caution
end run
APPLESCRIPT
    else
        message "Unmount and remount $DEVICE ($VOLUME_NAME) using $BACKEND? Close files on this drive first."
        printf 'Type yes to continue: ' >&2
        IFS= read -r response || return 1
        [ "$response" = yes ]
    fi
}

acquire_lock() {
    local cache="${HOME}/Library/Caches/mountfs"
    # Lock is per login user. Never automatically break an existing lock.
    (umask 077; mkdir -p "$cache") || return 1
    LOCK_DIR="$cache/$DEVICE.lock"
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        LOCK_DIR=
        fail "Another operation holds this device lock. If an earlier process crashed, inspect ~/Library/Caches/mountfs/$DEVICE.lock before removing it."
        return 1
    fi
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
}

same_volume() {
    local expected_device="$1" expected_uuid="$2"
    load_volume "$expected_device" identity "$expected_uuid" || return 1
    [ "$DEVICE" = "$expected_device" ] && [ "$VOLUME_UUID" = "$expected_uuid" ]
}

verify_write() {
    local expected_device="$1" expected_uuid="$2" expected_point="$3" probe
    same_volume "$expected_device" "$expected_uuid" || { message "Verification: selected device identity could not be confirmed."; return 1; }
    message "Verification state: device=$DEVICE; mounted=$MOUNTED; mountPoint=$MOUNT_POINT; readOnly=$READ_ONLY; expectedPoint=$expected_point"
    [ "$MOUNTED" = true ] || { message "Verification: no mount for the selected device in the mount table."; return 1; }
    [ "$MOUNT_POINT" = "$expected_point" ] || { message "Verification: mount path does not match this transaction."; return 1; }
    [ "$READ_ONLY" = false ] || { message "Verification: filesystem is mounted read-only."; return 1; }
    # mktemp creates exclusively; it cannot overwrite an existing user file.
    probe=$(mktemp "$expected_point/.mountfs-write-test.XXXXXXXX") || { message "Verification: current user could not create the test file (uid=$USER_ID, gid=$GROUP_ID)."; return 1; }
    if ! printf 'mouNTFS write verification\n' > "$probe"; then
        message "Verification: writing the test file failed."
        rm -f -- "$probe"
        return 1
    fi
    rm -- "$probe" || { message "Verification: deleting the test file failed: $probe"; return 1; }
}

recover_volume() {
    local expected_device="$1" expected_uuid="$2"
    message "Restoring the volume through macOS..."
    same_volume "$expected_device" "$expected_uuid" || {
        fail "Drive disappeared or its identity changed. Reconnect and inspect it; no recovery command was issued."
        return 1
    }
    if [ "$MOUNTED" = true ]; then
        # Do not unmount an unrelated mount created concurrently by another program.
        if [ "$MOUNT_POINT" = "$ORIGINAL_MOUNT_POINT" ]; then
            message "Original mount is still present; left unchanged."
            return 0
        fi
        if [ -z "$NEW_MOUNT_POINT" ] || [ "$MOUNT_POINT" != "$NEW_MOUNT_POINT" ]; then
            fail "A different mount appeared; left unchanged."; return 1
        fi
        run_privileged /usr/sbin/diskutil unmount "$expected_device" || return 1
    fi
    run_privileged /usr/sbin/diskutil mount readOnly "$expected_device" || {
        fail "Automatic read-only recovery failed. Use Disk Utility to inspect the drive."
        return 1
    }
    message "Read-only recovery completed."
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    if [ "$RECOVERY_NEEDED" -eq 1 ]; then
        recover_volume "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" || status=1
    fi
    if [ -n "$NEW_MOUNT_POINT" ]; then
        # Only remove our empty mount directory. rmdir never removes user files.
        # An active mount is deliberately retained, even if its root is empty.
        if same_volume "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" && [ "$MOUNT_POINT" != "$NEW_MOUNT_POINT" ]; then
            run_privileged /bin/rmdir "$NEW_MOUNT_POINT" >/dev/null 2>&1 || true
        fi
    fi
    if [ -n "$LOCK_DIR" ]; then
        rm -f -- "$LOCK_DIR/pid"
        rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
    if [ -n "$AUTH_SESSION_PID" ]; then
        kill "$AUTH_SESSION_PID" 2>/dev/null || true
        wait "$AUTH_SESSION_PID" 2>/dev/null || true
        AUTH_SESSION_PID=
    fi
    [ -z "$SESSION_DIR" ] || rm -rf -- "$SESSION_DIR"
    return "$status"
}

report_driver_failure() {
    local output
    output=$(cat "$1") || output=
    # ntfs-3g can append an unsafe-state hint after failing to open the device.
    # Report the concrete access failure before considering that generic hint.
    case "$output" in
        *"Operation not permitted"*|*"Permission denied"*)
            fail "ntfs-3g could not access the NTFS device. Allow the actual ntfs-3g executable in System Settings > Privacy & Security > Full Disk Access. Authorizing only mouNTFS may not cover the driver. Open Show Details for the driver path and error." ;;
        *"Unsupported macOS Version"*|*"the file system is not available"*)
            fail "macFUSE could not load the filesystem backend. Check the installed macFUSE version and macOS driver approval; Open Show Details." ;;
        *"hibernated"*|*"unsafe state"*|*"unclean"*)
            fail "ntfs-3g reported an unsafe NTFS state. Fully shut down or repair the volume in Windows; this tool will not force writing." ;;
        *) fail "ntfs-3g failed to mount the partition. Open Show Details for the driver error." ;;
    esac
}


mount_volume() {
    local options rc=0
    TRANSACTION_DEVICE="$DEVICE"
    TRANSACTION_UUID="$VOLUME_UUID"
    ORIGINAL_MOUNT_POINT="$MOUNT_POINT"
    acquire_lock || return 1
    same_volume "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" || return 1
    if [ "$MOUNTED" = true ] && [ "$READ_ONLY" = false ]; then
        message "Volume already reports writable; no remount performed."
        return 0
    fi
    confirm_mount || { message "Operation cancelled; the drive was not changed."; return 2; }
    start_authorization_session || return 1
    # Acquire CLI credentials before the first disk mutation.
    if [ "$GUI" -eq 0 ]; then /usr/bin/sudo -v || return 1; fi
    same_volume "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" || return 1
    message "[1/4] Preparing mount directory..."
    NEW_MOUNT_POINT=$(run_privileged /usr/bin/mktemp -d "/Volumes/mountfs.$TRANSACTION_DEVICE.XXXXXXXX") || {
        rc=$?
        if [ "$rc" -eq 2 ]; then message "Authorization cancelled; the drive was not changed."; return 2; fi
        return 1
    }
    # Only accept the controlled directory generated by the OS.
    [[ "$NEW_MOUNT_POINT" =~ ^/Volumes/mountfs\.disk[0-9]+s[0-9]+(s[0-9]+)?\.[A-Za-z0-9]+$ ]] || {
        NEW_MOUNT_POINT=; fail "Unexpected mount directory returned."; return 1;
    }
    message "[2/4] Unmounting volume..."
    if [ "$MOUNTED" = true ]; then
        # Arm recovery before unmount, including interrupted commands.
        RECOVERY_NEEDED=1
        run_privileged /usr/sbin/diskutil unmount "$TRANSACTION_DEVICE" || return 1
    else
        RECOVERY_NEEDED=1
    fi
    same_volume "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" || return 1
    [ "$MOUNTED" = false ] || { fail "Volume is still mounted; refusing a second mount."; return 1; }
    options="rw,norecover,allow_other,default_permissions,uid=$USER_ID,gid=$GROUP_ID,umask=077"
    if [ "$BACKEND" = fskit ]; then options="$options,backend=fskit"; else options="$options,local"; fi
    message "[3/4] Mounting with ntfs-3g ($BACKEND)..."
    run_privileged "$DRIVER" "/dev/$TRANSACTION_DEVICE" "$NEW_MOUNT_POINT" -o "$options" > "$SESSION_DIR/driver.log" 2>&1 || rc=$?
    cat "$SESSION_DIR/driver.log" >&2
    if [ "$rc" -ne 0 ]; then
        report_driver_failure "$SESSION_DIR/driver.log"
        return 1
    fi
    message "[4/4] Verifying write access as the current user..."
    # Retry metadata visibility, not the destructive mount operation.
    local attempt
    for attempt in 1 2 3; do
        message "Verification attempt $attempt/3"
        if verify_write "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" "$NEW_MOUNT_POINT"; then
            if [ "$AUTH_PRIVILEGED" -eq 1 ]; then
                "$AUTH_HELPER" --authorization-request "$SESSION_DIR" "$AUTH_SESSION_PID" --helper-commit || return 1
            fi
            RECOVERY_NEEDED=0
            message "Write access verified: $NEW_MOUNT_POINT"
            return 0
        fi
        sleep 1
    done
    fail "Mount returned success, but write access could not be verified."
}

diagnose() {
    local rc=0
    printf 'mouNTFS: %s\nmacOS: %s\nArchitecture: %s\n' "$MOUNTFS_VERSION" "$(/usr/bin/sw_vers -productVersion)" "$(uname -m)"
    if find_driver; then
        printf 'ntfs-3g: %s\n' "$DRIVER"
        printf 'Driver permissions: Full Disk Access must cover the actual ntfs-3g executable; mouNTFS access alone may not cover it.\n'
        printf 'Permission status: not programmatically verified. Check System Settings > Privacy & Security > Full Disk Access.\n'
    else rc=1; fi
    if [ -d /Library/Filesystems/macfuse.fs ]; then
        printf 'macFUSE bundle: installed (backend readiness requires a mount test)\n'
    else
        printf 'macFUSE bundle: missing\n'
        rc=1
    fi
    printf 'Requested backend: %s\n' "$BACKEND"
    check_backend || rc=1
    return "$rc"
}

usage() {
    cat <<'HELP'
mouNTFS — enable write access to external NTFS drives on macOS
Usage:
  ./mountfs.sh                         Native volume picker and system authorization
  ./mountfs.sh --device disk4s1         Select a partition directly; still confirms
  ./mountfs.sh --cli --device disk4s1   Terminal confirmation and sudo authentication
  ./mountfs.sh --list                  List external NTFS partitions (no authorization)
  ./mountfs.sh --diagnose              Check environment (no disk changes)
  ./mountfs.sh --backend fskit          Opt into experimental FSKit backend
  ./mountfs.sh --version | --help

Default backend: kernel. Requires macFUSE and Homebrew ntfs-3g-mac.
FSKit requires macOS 15.4+ and a compatible macFUSE/ntfs-3g combination.
Internal disks, forced recovery and clearing Windows hibernation are unsupported.
Exit codes: 0 success, 1 failure, 2 cancellation/invalid arguments, 130 interruption.
HELP
}

main() {
    local target='' action=mount rc
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help|-h) usage; return 0 ;;
            --version) printf '%s\n' "$MOUNTFS_VERSION"; return 0 ;;
            --cli) GUI=0 ;;
            --app-action) APP_ACTION=1 ;;
            --list) action=list; GUI=0 ;;
            --diagnose) action=diagnose ;;
            --device|--backend)
                [ "$#" -ge 2 ] || { usage >&2; return 2; }
                if [ "$1" = --device ]; then target="$2"; else BACKEND="$2"; fi
                shift ;;
            *) fail "Unknown argument: $1"; return 2 ;;
        esac
        shift
    done
    if [ "$APP_ACTION" -eq 1 ] && { [ "$GUI" -ne 1 ] || [ -z "$target" ] || [ "$action" != mount ]; }; then
        fail "App actions require an explicitly selected GUI volume."; return 2
    fi
    [ "$(uname -s)" = Darwin ] || { fail "mouNTFS requires macOS."; return 1; }
    [ "$(id -u)" -ne 0 ] || { fail "Run as your normal user, not with sudo."; return 1; }
    USER_ID=$(id -u); GROUP_ID=$(id -g)
    umask 077
    SESSION_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mountfs.XXXXXXXX") || return 1
    trap 'cleanup; exit $?' EXIT
    trap 'exit 130' INT TERM HUP
    case "$action" in
        list) select_volume; return $? ;;
        diagnose) diagnose; return $? ;;
    esac
    find_driver && check_backend || return 1
    if [ -z "$target" ]; then
        if [ "$GUI" -eq 0 ]; then fail "Use --list, then --cli --device diskNsM."; return 2; fi
        target=$(select_volume); rc=$?
        [ "$rc" -eq 0 ] || return "$rc"
    fi
    load_volume "$target" || return 1
    mount_volume
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; exit $?; fi
