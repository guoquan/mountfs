# Release validation

Status: **not yet validated on actual macOS disks**. Use disposable test drives.
Record macOS build, architecture, macFUSE/ntfs-3g versions, backend, UUID behavior,
authorization behavior and result for every run.

0.2.1 adds CI checks against the runner's real `diskutil info -plist /` output,
plus a modeled NTFS plist exercised with the actual PlistBuddy. This checks field
names and state parsing, but is not a physical NTFS USB drive mount test.

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
- Confirm `diskutil info -plist <device>` exposes DiskUUID (preferred), or VolumeUUID, and MountPoint after
  ntfs-3g mounting. The core fails closed if identity cannot be established.
- Complete Developer ID signing/notarization; test a downloaded app on a clean Mac.
- Publish versioned artifacts/checksums, then update the independent gh-pages website.
- Add localization and first-run guidance after the backend compatibility matrix is known.

0.2.2 addresses missing VolumeUUID by preferring the GPT partition DiskUUID.
Identifiers are namespaced to avoid confusing partition and filesystem UUIDs.
Disks exposing neither remain blocked; device numbers/names are not safe identity
fallbacks. Real GPT and MBR NTFS drives, plus UUID visibility after FUSE mounting,
still need validation. The local scan report records only identity availability.

The app now builds AppIcon.icns and a template menu bar mark from the website's
italic m/upright N branding. CI checks icon packaging; Finder rendering and menu
bar legibility in light/dark mode require a Mac check.
