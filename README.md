# *mouNT*FS

A native macOS menu bar app for enabling write access to external NTFS partitions,
using macFUSE and ntfs-3g. Insert a drive, select **Enable Write Access…**, and open
it in Finder after write access is verified. Insertion never mounts a drive writable
on its own.

**Current development version: 0.3.4.** Builds are ad-hoc signed and not notarized.
Use the mounting steps below; experimental authorization settings are not needed
for this flow. Future authorization improvements are described in the roadmap.

[中文使用与故障说明](docs/USAGE.zh-CN.md) ·
[Roadmap](ROADMAP.md) ·
[Authorization architecture](docs/AUTHORIZATION.md) ·
[Validation status](docs/VALIDATION.md)

## What it does

- Shows external NTFS partitions and their mounted/read-only/writable state.
- Provides write access, Finder and confirmed whole-disk safe eject actions.
- Refreshes every five seconds and after mount/unmount notifications.
- Shows progress without opening Terminal; successful actions do not open a log window.
- Opens Finder after verified mounting by default; Settings can disable this.
- Includes the branded application icon and a native template menu bar mark.
- Keeps diagnostics and the latest operation log available for copying.

The mount core rejects internal disks and whole-disk mount targets, pins the selected
partition identity, avoids force-unmount and uses `norecover`. It verifies write
access by exclusively creating, writing and removing a temporary file as the current
user. Failure triggers best-effort recovery of the same partition through macOS.
These precautions do not establish compatibility with every disk or driver version.

## Drivers and permissions

The app requires macOS 13+ and separately installed Homebrew drivers:

```bash
brew install --cask macfuse
brew install gromgit/fuse/ntfs-3g-mac
```

Follow the [macFUSE installation guide](https://github.com/macfuse/macfuse/wiki/Getting-Started)
for OS compatibility, system approval and restart requirements. The default kernel
backend requires kernel-extension approval; Apple Silicon setup may require a
startup security change in Recovery. The app does not install drivers or change
security policy. FSKit is an explicit experimental option for macOS 15.4+ with a
compatible driver combination; it has no physical-drive validation in this project.

Administrator authorization and Full Disk Access are separate. In the reported
working setup, granting **the actual ntfs-3g executable** Full Disk Access was
sufficient even with mouNTFS Full Disk Access disabled. Common driver locations are
`/opt/homebrew/bin/ntfs-3g` and `/usr/local/bin/ntfs-3g`; use installation diagnostics
to identify yours. The app cannot verify macOS privacy permission status. Other
macOS/driver combinations may differ.

## Install or build the app

Successful macOS [Actions runs](https://github.com/guoquan/mountfs/actions) provide
`mouNTFS-0.3.4-development-app` artifacts containing a versioned archive such as
`mouNTFS-0.3.4-dev-arm64.zip`. Download the artifact for the desired commit and
extract the contained app. **The bundle is always `mouNTFS.app`.** Quit the old app
before replacing `/Applications/mouNTFS.app`, then open the replacement there.
The menu header displays its version. These development downloads are not a
notarized public release and do not bypass Gatekeeper.

To build locally on macOS with Xcode Command Line Tools, from this checkout:

```bash
bash scripts/build-app.sh
open dist/mouNTFS.app
```

Command Line Tools are sufficient for this ad-hoc build and ordinary mounting.
The UI is currently English; localization and a first-run setup wizard are pending.

## Use the menu

1. Connect an external NTFS drive and open the mouNTFS menu.
2. Check the partition name and choose **Enable Write Access…**.
3. Confirm the action and complete any macOS administrator authorization.
4. Wait for verification. Finder opens by default after success.
5. Close files using the drive before **Safely Eject…**. Ejection applies to the
   physical disk and its other partitions, as stated in the confirmation.

Settings includes Finder opening and the optional volume count. Experimental
authorization controls are not part of the standard setup. Diagnostics includes disk scan, installation diagnosis, the last
operation and report copying. Other disk actions and quitting are disabled while
an operation is in progress. macOS requests administrator authorization when needed; prompt counts can vary.
mouNTFS does not save your password.

## Troubleshooting

| Symptom | Meaning and next step |
|---|---|
| No external NTFS partition appears | Run **Show Disk Scan Report…**; inspect exclusion reasons. Whole disks and non-NTFS filesystems are excluded. |
| `Operation not permitted` while opening `/dev/disk…` | Check Full Disk Access for the actual ntfs-3g driver. Administrator approval alone does not grant it. A generic unsafe-state hint after this error does not establish Windows hibernation. |
| macFUSE says the OS version is unsupported | Update to an OS-compatible macFUSE version and follow its approval/restart instructions. |
| Mount reports success but write verification fails | Read Show Details for mount source/path/flags and write-probe errors. Driver success alone is not proof of writable access. |
| A confirmed hibernated/unclean NTFS error | Fully shut down or repair the volume in Windows. mouNTFS does not clear hibernation or force writing. |
| Missing UUID | The bundled metadata tool can use a live IOMedia connection identity; missing UUID alone is not a reason to reformat. |

## Planned improvements

The next stages focus on fewer authorization prompts, native Touch ID confirmation,
clearer setup guidance and a polished interface. See [ROADMAP](ROADMAP.md) for stage
order and acceptance criteria. Planned features are not requirements for using the
current mounting flow.

## Standalone script and recovery boundaries

The script in this checkout can also be used independently. The separate website
download endpoint has not been updated by this branch.

```bash
bash mountfs.sh                       # native picker and system authorization
bash mountfs.sh --list                # external NTFS partitions
bash mountfs.sh --diagnose            # read-only environment check
bash mountfs.sh --device disk4s1      # example only; still confirms
bash mountfs.sh --cli --device disk4s1
bash mountfs.sh --backend fskit        # explicit experimental backend
```

Run as your normal user; CLI mode requests sudo itself. Identify the actual
partition using `--list`, not a copied device number. Finder does not reliably
execute `.sh` on double-click. Exit codes: 0 success, 1 failure,
2 cancellation/invalid arguments, 130 interruption.

The core uses a stable partition/volume UUID or live IOMedia connection identity;
standalone use without the bundled metadata tool retains a validated NTFS boot-record
fallback. Identity is pinned through verification and recovery. Connection identity
is not stored across sessions. Raw boot-record access can require authorization and
privacy permissions. Device names/numbers alone are not accepted as stable identity.

Mount directories use `/Volumes/mountfs.diskNsM.<random>` and current-user uid/gid
with `umask=077`. Already-writable volumes are left unchanged based on metadata;
that message does not claim a fresh write probe. The old fixed `.write_test` filename
is never used. Failed transactions attempt same-identity recovery; a changed or
missing disk prevents recovery against a replacement. Busy disks, cancellation and
OS errors can prevent recovery. Inspect the log and Disk Utility in that case.

Locks coordinate this app's operations for the same user, not all users and tools.
A crash can leave `~/Library/Caches/mountfs/diskNsM.lock`: inspect its `pid`, confirm
the process stopped and inspect the drive before removing it manually. Signal
cleanup is best-effort and cannot handle SIGKILL, power loss or every hot-plug race.

## Development and validation

```bash
bash -n mountfs.sh
bash tests/core_tests.sh
bash tests/ntfs_identity_tests.sh
bash tests/media_identity_tests.sh
bash tests/mount_state_tests.sh
swift test                           # macOS only
```

CI also runs ShellCheck, real macOS metadata/mount-table checks, signing-pin checks
and disposable root launchd XPC status checks. It does not establish SMAppService
registration, protected-driver mounting, Touch ID or real NTFS hot-plug behavior.
See [the validation record](docs/VALIDATION.md) for reported successes, known failures
and remaining tests. Public distribution still needs appropriate Developer ID
signing, notarization and broader physical-drive validation.

## Human–AI collaboration

Humans direct design, review and testing; AI assists with implementation.
Contributions and safety reviews are welcome. Original collaborators:
Claude 3.5 Sonnet, GPT-4o and [guoquan](https://guoquan.net).
The current development update was prepared with Codex.

MIT License © 2024–2026 Quan Guo.
