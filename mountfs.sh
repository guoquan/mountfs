#!/bin/bash
# mouNTFS — MIT License, Copyright (c) 2024-2026 Quan Guo.
# See LICENSE for the full license text.
# Compatible with the Bash 3.2 shipped by macOS. No password is read by this script.

MOUNTFS_VERSION=0.2.1
GUI=1
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
    local target="$1" policy="${2:-ntfs}" info="$SESSION_DIR/info.plist" fs whole
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
    VOLUME_UUID=$(plist_value "$info" VolumeUUID) || {
        fail "Cannot establish a stable volume identity."; return 1;
    }
    [ -n "$VOLUME_UUID" ] || return 1
    VOLUME_NAME=$(plist_value "$info" VolumeName) || VOLUME_NAME="$DEVICE"
    load_mount_state "$info"
}

load_mount_state() {
    local info="$1" writable
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
    load_volume "$expected_device" identity || return 1
    [ "$DEVICE" = "$expected_device" ] && [ "$VOLUME_UUID" = "$expected_uuid" ]
}

verify_write() {
    local expected_device="$1" expected_uuid="$2" expected_point="$3" probe
    same_volume "$expected_device" "$expected_uuid" || return 1
    [ "$MOUNTED" = true ] && [ "$MOUNT_POINT" = "$expected_point" ] || return 1
    [ "$READ_ONLY" = false ] || return 1
    # mktemp creates exclusively; it cannot overwrite an existing user file.
    probe=$(mktemp "$expected_point/.mountfs-write-test.XXXXXXXX") || return 1
    if ! printf 'mouNTFS write verification\n' > "$probe"; then
        rm -f -- "$probe"
        return 1
    fi
    rm -- "$probe" || return 1
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
    [ -z "$SESSION_DIR" ] || rm -rf -- "$SESSION_DIR"
    return "$status"
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
    # Acquire CLI credentials before the first disk mutation.
    if [ "$GUI" -eq 0 ]; then /usr/bin/sudo -v || return 1; fi
    same_volume "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" || return 1
    message "[1/4] Preparing mount directory..."
    NEW_MOUNT_POINT=$(run_privileged /usr/bin/mktemp -d "/Volumes/mountfs.$TRANSACTION_DEVICE.XXXXXXXX") || return 1
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
    run_privileged "$DRIVER" "/dev/$TRANSACTION_DEVICE" "$NEW_MOUNT_POINT" -o "$options" || rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "Driver failed. Hibernated or unclean volumes must be shut down/repaired in Windows; this tool will not force them writable."
        return 1
    fi
    message "[4/4] Verifying write access as the current user..."
    # Retry metadata visibility, not the destructive mount operation.
    local attempt
    for attempt in 1 2 3; do
        message "Verification attempt $attempt/3"
        if verify_write "$TRANSACTION_DEVICE" "$TRANSACTION_UUID" "$NEW_MOUNT_POINT"; then
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
    if find_driver; then printf 'ntfs-3g: %s\n' "$DRIVER"; else rc=1; fi
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
    load_volume "$target" || { fail "Cannot load the selected external NTFS partition."; return 1; }
    mount_volume
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; exit $?; fi
