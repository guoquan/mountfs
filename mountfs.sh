#!/bin/bash

# MIT License
# 
# Copyright (c) 2024 Quan Guo
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Ensure proper terminal session
if [ ! -t 1 ]; then
    # Get the default terminal application
    default_terminal=$(osascript -e '
        try
            tell application "System Events"
                return name of first application process whose frontmost is true and background only is false and name contains "Term"
            end tell
        on error
            return "Terminal"
        end try
    ')
    
    # Launch in the detected terminal directly
    open -a "$default_terminal" -n --args "$0"
    exit 0
fi

# Function to get disk information
get_disk_info() {
    local mount_point="$1"
    local device="$2"
    local info=$(diskutil info "$device")
    
    # Get volume name and basic info
    printf "Volume Name:    %s\n" "$(basename "$mount_point")"
    printf "Device:         %s\n" "$device"
    printf "File System:    %s\n" "$(echo "$info" | grep "Type (Bundle):" | cut -d: -f2- | xargs)"
    
    # Get size information using df -h for human-readable format
    local df_info=$(df -h "$device" | tail -n 1)
    local used=$(echo "$df_info" | awk '{print $3}')
    local total=$(echo "$df_info" | awk '{print $2}')
    printf "Size:           %s / %s\n" "$used" "$total"
    
    # Check if read-only
    local mount_info=$(mount | grep "$device")
    if [[ $mount_info == *"read-only"* ]] || [[ $mount_info == *"(ro"* ]]; then
        printf "Status:         Currently Read-Only\n"
    else
        printf "Status:         Read-Write\n"
    fi
}

# Function to show confirmation dialog
show_confirmation() {
    local mount_point="$1"
    local device="$2"
    local disk_info=$(get_disk_info "$mount_point" "$device")
    local response
    response=$(osascript -e "display dialog \"Selected Volume:\n$disk_info\n\nThis operation will:\n• Request administrator password (in a popup dialog)\n• Unmount and remount the NTFS volume\n• Enable write access to the volume\" buttons {\"Cancel\", \"OK\"} default button \"OK\" with icon caution")
    [[ $response == *"OK"* ]]
}

# Function to get filesystem type
get_volume_fs_type() {
    local mount_point="$1"
    local device=$(df "$mount_point" | grep "^/dev" | awk '{print $1}')
    [ -n "$device" ] && diskutil info "$device" | grep "Type (Bundle):" | awk '{print $NF}'
}

# Function to select a mount point using AppleScript
select_mount_point() {
    local mount_point
    mount_point=$(osascript -e 'try
        set volumePath to POSIX file "/Volumes" as alias
        set selectedFolder to choose folder with prompt "Select NTFS volume to mount:" default location volumePath
        POSIX path of selectedFolder
    on error
        return "cancelled"
    end try' 2>/dev/null)

    # Check if cancelled
    [ "$mount_point" = "cancelled" ] && {
        echo "Selection cancelled by user." >&2
        return 1
    }

    # Remove trailing slash if present
    mount_point="${mount_point%/}"

    # Verify it's an NTFS volume
    local fs_type=$(get_volume_fs_type "$mount_point")
    if [ "$fs_type" != "ntfs" ]; then
        echo "Error: Selected volume is not NTFS (type: $fs_type)" >&2
        return 1
    fi

    # Get device path
    local device=$(df "$mount_point" | grep "^/dev" | awk '{print $1}')
    if [ -z "$device" ]; then
        echo "Error: Could not determine device for mount point" >&2
        return 1
    fi

    # Return mount point and device path as a single line
    printf "%s\t%s" "$mount_point" "$device"
}

# Function to get sudo password via GUI
get_sudo_password() {
    # Skip terminal activation - let the dialog handle focus
    osascript -e 'text returned of (display dialog "Please enter administrator password:" with title "Sudo Authentication" default answer "" buttons {"Cancel", "OK"} default button "OK" with hidden answer)'
}

# Function to remount NTFS volume with write access
remount_ntfs() {
    local mount_point="$1"
    local device="$2"
    
    # Debug output
    echo "Debug: mount_point=$mount_point"
    echo "Debug: device=$device"
    
    # Request sudo access if needed
    echo "Requesting administrator privileges..."
    local password
    password=$(get_sudo_password) || {
        echo "Error: Administrator privileges required" >&2
        return 1
    }
    
    # Verify sudo access with the password
    if ! echo "$password" | sudo -S -v 2>/dev/null; then
        echo "Error: Invalid password" >&2
        return 1
    fi
    
    # Run all mount operations in a single sudo session
    echo "$password" | sudo -S bash -c "
# Debug inside sudo
echo 'Debug inside sudo:'
echo 'mount_point=$mount_point'
echo 'device=$device'

# Unmount first
echo 'Unmounting volume...'
diskutil unmount '$mount_point' || exit 1

# Try mount_ntfs first (built-in)
echo 'Trying mount_ntfs...'
mount_ntfs -o rw '$device' '$mount_point' 2>&1
mount_status=\$?
echo 'mount_ntfs status: '\$mount_status
[ \$mount_status -eq 0 ] && exit 0

# Fallback to ntfs-3g if available
if command -v ntfs-3g >/dev/null 2>&1; then
    echo 'mount_ntfs failed, trying ntfs-3g...'
    ntfs-3g '$device' '$mount_point' -o local,allow_other,remove_hiberfile,force 2>&1
    exit \$?
fi

exit 1
"
    local mount_status=$?
    
    # Clear password from memory
    password=""
    
    [ $mount_status -eq 0 ] || return 1
    
    sleep 2
    
    # Verify mount and write access
    if mount | grep -q "$mount_point"; then
        if touch "$mount_point/.write_test" 2>/dev/null; then
            rm "$mount_point/.write_test"
            echo "Successfully mounted with write access"
            return 0
        fi
        echo "Warning: Volume mounted but might be read-only" >&2
    else
        echo "Error: Mount failed" >&2
        diskutil mount "$device" >/dev/null 2>&1
    fi
    return 1
}

# Main script execution
main() {
    # Get mount point and device path
    local result
    result=$(select_mount_point) || exit 1
    MOUNT_POINT=$(echo "$result" | cut -f1)
    DEVICE=$(echo "$result" | cut -f2)
    
    show_confirmation "$MOUNT_POINT" "$DEVICE" && {
        remount_ntfs "$MOUNT_POINT" "$DEVICE"
    } || echo "Operation cancelled"
}

# Run main if script is executed directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main 