# Release validation

Status: **not yet validated on actual macOS disks**. Use disposable test drives.
Record macOS build, architecture, macFUSE/ntfs-3g versions, backend, UUID behavior,
authorization behavior and result for every run.

| Scenario | Expected result | Actual |
|---|---|---|
| Clean NTFS, kernel, Intel and Apple Silicon | Verified write and Finder access | Pending |
| Compatible FSKit, macOS 15.4+ | Mount, identity metadata, write and eject | Pending |
| Unicode, quotes and spaces in volume name | Correct selection; no interpolation | Pending |
| Missing driver / macFUSE not ready | Clear error; mount retained/restored | Pending |
| Cancel confirmation | No disk change | Pending |
| Cancel authorization | No mutation or explicit recovery failure | Pending |
| Busy unmount | No force; existing mount retained | Pending |
| Failed driver / false-success mount / failed probe | Read-only recovery | Pending |
| Hibernated or dirty NTFS | No forced write or hibernation removal | Pending |
| Unplug and replace during transaction | No recovery against replacement UUID | Pending |
| Existing `.write_test` file | Contents untouched | Pending |
| Concurrent operations, same user | Second operation refused | Pending |
| SIGINT/SIGTERM during operation | Best-effort recovery and cleanup | Pending |
| Eject a multi-partition disk | Confirmed OS-managed whole-disk eject | Pending |
| Native app launch | Menu, dialogs and output work | Pending |

Before public distribution:

- Verify driver options with pinned versions, especially FSKit permissions.
- Confirm `diskutil info -plist <device>` exposes VolumeUUID and MountPoint after
  ntfs-3g mounting. The core fails closed if identity cannot be established.
- Complete Developer ID signing/notarization; test a downloaded app on a clean Mac.
- Publish versioned artifacts/checksums, then update the independent gh-pages website.
- Add localization and first-run guidance after the backend compatibility matrix is known.
