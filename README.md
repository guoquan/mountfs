# *mouNT*FS

Enable write access to external NTFS drives on your Mac. **0.2.11 is a development
update, pending actual macOS/NTFS drive validation.** It includes a native menu bar
app and a rewritten standalone script. It is not yet a notarized public app release.

0.2.1 fixes volume detection by using macOS's actual `WholeDisk`, `WritableVolume`
and `MountPoint` plist fields. It adds live macOS schema checks, mount/unmount
refresh, a detected-volume count beside the menu icon, and a local **Show Disk Scan
Report…** command. Inserting a disk updates the menu; select the drive and choose
**Enable Write Access…** to mount it writable. Insertion does not mount automatically.

## Features

- Native menu bar: volume list, enable writing, Finder, safe eject, installation
  diagnosis, and refresh every five seconds. No automatic mounting.
- Bash 3.2-compatible core, structured disk metadata and per-user device locks.
- macOS system authorization; CLI uses sudo directly. No custom password input.
- Exclusive temporary write probes and best-effort read-only recovery on failure.
- No force-unmount, clearing Windows hibernation, or forced NTFS recovery.
- Explicit experimental FSKit option; kernel backend remains the default.
- Regression simulations and CI. See [release validation](docs/VALIDATION.md).

## Install drivers

Requires macOS, Homebrew, macFUSE and ntfs-3g-mac:

```bash
brew install --cask macfuse
brew install gromgit/fuse/ntfs-3g-mac
```

Follow the current [macFUSE installation guide](https://github.com/macfuse/macfuse/wiki/Getting-Started).
The kernel backend requires kernel-extension approval, and on Apple Silicon may
require changing startup security policy in Recovery Mode. FSKit is a user-space
backend available from macOS 15.4 and does not require that kernel-extension setup.
Actual backend support depends on installed macOS/macFUSE/ntfs-3g versions.
This tool does not install drivers or change security policies automatically.

## Build the menu bar app

Requires macOS 13+ and Xcode command line tools. From the checkout:

```bash
bash scripts/build-app.sh
open dist/mouNTFS.app
```

Successful macOS CI runs also provide a `mouNTFS-<version>-development-app` download artifact
on the Actions run page. It is an ad-hoc signed development build, not notarized.

Select a drive and **Enable Write Access…**. That menu action confirms the
operation; macOS still handles administrator authorization. A spinning menu bar
icon indicates work in progress. Successful mounting/ejection does not open a log
window. **Diagnostics → Show Last Operation…** keeps the latest operation log.
Finder opens after verified mounting by default; the menu preference can disable
this. Installation diagnosis and failures still offer their requested details. Other disk actions and quitting are disabled
during the operation. Output appears in a selectable window. **Safely Eject…**
confirms before ejecting the physical disk, including its other partitions.

The build ad-hoc signs for local development. Public distribution still requires
Developer ID signing and notarization; this does not bypass Gatekeeper. The first
app version has English UI; localization and a first-run setup wizard are pending.

## Standalone script

Use the script from this checkout; the separate website download endpoint has not
been changed by this update.

```bash
bash mountfs.sh                       # native picker and system authorization
bash mountfs.sh --list                # enumerate external NTFS partitions
bash mountfs.sh --diagnose            # environment check; no disk changes
bash mountfs.sh --device disk4s1      # still confirms
bash mountfs.sh --cli --device disk4s1
bash mountfs.sh --backend fskit        # opt into experimental FSKit
```

Use `--list` to identify your partition; `disk4s1` is only an example. Run as your
normal user, not with sudo. Finder does not reliably execute `.sh` on double-click;
use the app or Terminal. The script no longer opens Terminal when there is no TTY.
Exit codes: 0 success, 1 failure, 2 cancellation/invalid arguments, 130 interruption.

## Mounting and recovery

External NTFS partitions require a stable partition/volume UUID or a live IOMedia
connection identity (validated boot-record fallback for standalone use). Internal
and whole disks are rejected. The core checks the drive and driver, obtains a device
lock, confirms, creates a unique `/Volumes/mountfs.diskNsM.<random>` directory,
unmounts without force, mounts with ntfs-3g, and verifies a private file can be
created/written/removed as the current user. Permissions use your uid/gid and
`umask=077`. Already-writable volumes are left unchanged based on metadata; that
message does not claim a fresh write test.

Failed transactions attempt to restore the same volume read-only through macOS.
Recovery is not issued if the disk disappeared or its pinned identity changed; unrelated
mounts are left alone. Authorization cancellation, busy disks or OS errors can
prevent recovery: inspect the output and Disk Utility. Signal handling is best-effort;
it cannot handle SIGKILL/power loss or eliminate every hot-plug race.

Hibernated or unclean volumes are refused using `norecover`. Fully shut down or
repair the drive in Windows. The old `remove_hiberfile,force` defaults are removed.
The fixed `.write_test` filename is no longer touched.

Locks coordinate operations by the same user, not other users/tools. A crash can
leave `~/Library/Caches/mountfs/diskNsM.lock`: inspect its `pid`, confirm the process
has stopped and inspect the drive before removing the lock manually.

## Development

```bash
bash -n mountfs.sh
bash tests/core_tests.sh
shellcheck mountfs.sh scripts/build-app.sh tests/core_tests.sh
swift build                          # macOS only
```

Tests simulate success, cancellation, busy disks, driver failure, false-success
read-only mounts, failed probes, unplugged/replaced disks and metadata validation.
A filesystem test verifies exclusive probes preserve existing user files.
Simulations and compilation do not establish real-drive compatibility.

## Human–AI collaboration

AI writes code while humans direct design and review. Contributions, testing and
safety reviews are welcome. Original collaborators: Claude 3.5 Sonnet, GPT-4o and
[guoquan](https://guoquan.net). The 0.2.0 development update was prepared with Codex.
MIT License © 2024-2026 Quan Guo.

Development archives and Actions artifacts include version numbers; the bundle
is always `mouNTFS.app`, so it can replace the installed app. Version 0.2.11 is
shown in the menu header and the bundle metadata. Quit the old app before replacing
it, and launch the replacement. The current build remains ad-hoc signed.
Show Details includes each write-verification condition and filesystem errors.
The bundled helper reads IOMedia connection identities and the kernel mount table,
so FUSE write verification does not depend on diskutil recognizing the filesystem.
Standalone shell use without the helper retains the boot-record identity fallback.

0.2.10 restores the bounded authorization-session implementation from 0.2.8 after
user testing confirmed it works with Full Disk Access granted to ntfs-3g. A single
unprivileged host owns one compiled AppleScript instance for mounting, recovery
and directory cleanup. The command allowlist remains pinned to one connected
partition, controlled mount directory and login uid/gid. Sessions end on cleanup,
parent termination or a five-minute limit; no password/token is saved and no
privileged daemon is installed. Touch ID-only administrator authorization remains
unimplemented.

Driver permissions matter separately from administrator authorization: in the
reported macOS setup, ntfs-3g Full Disk Access was sufficient even with mouNTFS
Full Disk Access disabled. Grant access to the actual installed ntfs-3g executable
in System Settings → Privacy & Security → Full Disk Access. Installation diagnosis
and access-error messages explain this requirement; the app does not claim to
inspect or verify TCC permission status. Other macOS/driver combinations still
require validation. Concrete device-open denial takes precedence over the driver's
generic unsafe-state hint.


## Menu and authorization roadmap

0.2.11 groups each drive's status and actions directly in the main menu. Enable
Write Access, Open in Finder and Safely Eject no longer require a drive submenu.
The branded header, system symbols and semantic colors follow native appearance.
Settings contains the Finder preference and an optional menu-bar volume count
(off by default). Diagnostics has a Copy Report action. Permission errors offer
a shortcut to Full Disk Access; this opens settings without modifying permissions.
Completion messages return to the current volume summary after eight seconds.

Touch ID administrator authorization is still not implemented. LocalAuthentication
provides identity verification, not a root execution channel. The proposed next
step is an opt-in SMAppService helper with authenticated clients and narrowly
scoped mount requests; see [authorization design](docs/AUTHORIZATION.md). Adding a
fingerprint prompt before the current AppleScript would add a prompt without
removing the administrator password requirement.
