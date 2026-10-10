# Release validation

Status: **limited user-reported physical-drive validation; full matrix pending**. Use disposable test drives.
Record macOS build, architecture, macFUSE/ntfs-3g versions, backend, UUID behavior,
authorization behavior and result for every run.

0.2.1 adds CI checks against the runner's real `diskutil info -plist /` output,
plus a modeled NTFS plist exercised with the actual PlistBuddy. This checks field
names and state parsing, but is not a physical NTFS USB drive mount test.

| Scenario | Expected result | Actual |
|---|---|---|
| Clean NTFS, kernel, Intel and Apple Silicon | Verified write and Finder access | User-reported write verification on one Apple Silicon NTFS drive; Intel and wider matrix pending |
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
0.2.3 adds a read-only NTFS boot-record fingerprint for disks exposing neither.
Device numbers/names are not safe identity fallbacks. Real GPT and MBR NTFS drives, plus UUID visibility after FUSE mounting,
still need validation. The local scan report records only identity availability.

The app now builds AppIcon.icns and a template menu bar mark from the website's
italic m/upright N branding. CI checks icon packaging; Finder rendering and menu
bar legibility in light/dark mode require a Mac check.

0.2.3 reads 512 bytes from the validated raw external partition using od. It tries
an unprivileged read, then requests OS authorization only when necessary. The
NTFS OEM signature, sector/cluster sizes, sector trailer and nonzero serial and
geometry must pass validation. SHA-256 covers the entire record. Once selected,
this identity source is pinned for verification/recovery even if UUID metadata
later appears. Read failure or a changed record stops further disk operations.
Layout reference: https://github.com/torvalds/linux/blob/master/fs/ntfs3/ntfs.h

Five simulated boot-identity groups cover absent UUIDs, metadata appearance,
changed serial, malformed/truncated records, read authorization failure and
replacement refusal. They do not establish actual raw-device read behavior.
Validate MBR/GPT USB drives with no UUID before/after unmount and FUSE mounting,
macOS disk-access permissions, authorization cancellation and unplug/replacement.
A byte-identical cloned volume shares this fingerprint, as cloned UUIDs do; this
is accidental replacement protection, not hardware authentication.

0.2.4 replaces direct raw-device od reads with one aligned 4096-byte dd read.
The constant pipeline runs with pipefail and passes the validated device as an
argument, not interpolated source. od converts all bytes and only the first 512
are validated/hashed. Errors identify authorization/read failure, output length,
OEM signature, trailer, sector/cluster sizes, serial or geometry. A real dd/od
regular-file fixture runs on both CI platforms, including read-failure handling;
physical-device alignment and permissions still require user testing.
Build bundles/archives and Actions artifact names now include the version.

0.2.5 adds a bundled, unprivileged IOKit metadata executable for UUID-less devices.
Identity includes the partition registry ID, parent whole-media registry ID and
size. This connection-scoped token is never stored or reused across process/boot
sessions. Its source is pinned during the transaction. Replacement, disappearance
or helper failure stops operations instead of switching to an alternate source.
It does not open /dev, request administrator access or read filesystem content.
The GUI also opens/closes the mounted root to trigger scoped removable-volume
consent before spawning the core. Apple's privacy UI remains user-controlled.

Four simulated groups validate no raw reads, source pinning, replacement/parent
changes and malformed/unavailable identity. CI queries a real IOMedia twice and
validates invalid input/nonexistent-device rejection. Actual IOMedia stability
across NTFS unmount/FUSE remount, TCC consent and driver raw access remain pending.

## User-reported test, 2026-10-10

Environment: macOS 27.0.1, arm64, kernel backend, external NTFS volume LMT,
missing DiskUUID/VolumeUUID, Homebrew ntfs-3g at /opt/homebrew/bin/ntfs-3g.
Exact macFUSE and ntfs-3g versions were not captured.

- 0.2.6 log showed native mount visibility on the second verification attempt and
  a successful current-user exclusive write probe.
- 0.2.8 initially failed opening the device with EPERM, as did 0.2.9 after reverting
  the authorization host. App Full Disk Access alone did not resolve the failure.
- User granted ntfs-3g Full Disk Access and reported successful operation even
  with mouNTFS Full Disk Access disabled, then confirmed 0.2.8 works on retry.
- 0.2.10 restores that tested authorization-session implementation and combines
  it with specific driver permission guidance and diagnostic error precedence.

These are user reports, not independently reproduced lab tests. Session expiry,
authorization cancellation, hot-plug/replacement, Intel, FSKit and broader driver
version compatibility remain pending. Touch ID-only authorization is unimplemented.
