# *mouNT*FS

**English** · [简体中文](README.zh-CN.md)

### Your NTFS drive, from the macOS menu bar

Connect an external NTFS drive, enable write access, and continue in Finder.
mouNTFS now has a native menu bar app with visible drive states, progress feedback
and copyable diagnostics. The standalone shell script remains available for CLI use.

**Current version: 0.3.4 development build.** Requires separately installed macFUSE
and ntfs-3g. Development downloads are ad-hoc signed and not notarized.

[Get started](docs/USAGE.en.md) · [Downloads](https://github.com/guoquan/mountfs/actions) · [Roadmap](ROADMAP.md)

## See the app

| Select a drive | Write access enabled |
|---|---|
| ![Native menu with a read-only example drive](docs/images/menu-readonly.png) | ![Native menu with a writable example drive](docs/images/menu-writable.png) |

<details>
<summary>Operation progress and diagnostics</summary>

| Operation in progress | Copyable operation report |
|---|---|
| ![Native menu during an example operation](docs/images/menu-progress.png) | ![Native diagnostic window showing an example report](docs/images/diagnostics.png) |

</details>

These captures use the actual macOS app UI with **sample drive data and an example
log**. No disk was mounted to create them. The current UI is English.

## What has changed

| Earlier script workflow | Current app experience |
|---|---|
| Run commands in Terminal | Select the drive from a native menu |
| Read command output to understand state | See read-only/writable state beside each drive |
| Follow logs during an operation | Progress feedback; quiet completion; logs available when needed |
| Locate the mounted volume yourself | Finder opens after verified mounting by default |
| Gather troubleshooting output manually | Disk scan, installation diagnosis and copyable reports |

The app also includes branded icons, safe eject confirmation, automatic list refresh
and preferences for Finder opening and the menu bar volume count. It never enables
writing just because a drive was connected.

## Quick start

Requires macOS 13+, Homebrew and compatible drivers:

```bash
brew install --cask macfuse
brew install gromgit/fuse/ntfs-3g-mac
```

Follow the [macFUSE setup guide](https://github.com/macfuse/macfuse/wiki/Getting-Started)
for system approval and restart requirements. Download a successful macOS build
from [Actions](https://github.com/guoquan/mountfs/actions), extract the archive, and
place **mouNTFS.app** in Applications.

1. Connect the drive and open the mouNTFS menu.
2. Select **Enable Write Access…** and complete macOS authorization.
3. Wait for write verification; Finder opens by default.
4. Close files before **Safely Eject…**, which ejects the physical disk.

If macOS denies device access, check Full Disk Access for the actual **ntfs-3g**
executable. Administrator authorization is a separate permission.
[The usage guide](docs/USAGE.en.md) covers setup, updates and troubleshooting.
Experimental authorization settings are not required for the standard workflow.

## Safety and compatibility

mouNTFS targets external NTFS partitions, checks the selected device identity,
verifies writing as the current user and attempts same-volume read-only recovery
on failure. It does not force-unmount, clear Windows hibernation or format a drive.
Recovery can still fail; inspect diagnostics and Disk Utility if an operation fails.

Ordinary mounting has limited user-reported success on Apple Silicon. Other drive,
OS and driver combinations require further testing. See the [validation record](docs/VALIDATION.md)
for the evidence and remaining checks. FSKit remains experimental.

## Documentation

| For users | English | 简体中文 |
|---|---|---|
| Overview | [README](README.md) | [项目介绍](README.zh-CN.md) |
| Setup, use and troubleshooting | [Usage guide](docs/USAGE.en.md) | [使用说明](docs/USAGE.zh-CN.md) |

Development documentation is maintained in English:

- [Roadmap](ROADMAP.md): planned stages and acceptance criteria.
- [Authorization architecture](docs/AUTHORIZATION.md): permission helper, signing and Touch ID boundaries.
- [Validation record](docs/VALIDATION.md): CI, physical-Mac reports and remaining tests.
- [Contributing and documentation](CONTRIBUTING.md): local builds, checks and screenshot capture.

## Build and contribute

On macOS with Xcode Command Line Tools, from a checkout:

```bash
bash scripts/build-app.sh
open dist/mouNTFS.app
```

Download archives include a version number; the app stays **mouNTFS.app** so updates
can replace it. Quit the old app before replacing it. The separate website download
endpoint has not been updated by this development branch.

Humans direct design, review and testing; AI assists with implementation.
Original collaborators: Claude 3.5 Sonnet, GPT-4o and [guoquan](https://guoquan.net).
The current development update was prepared with Codex. Contributions and safety
reviews are welcome.

MIT License © 2024–2026 Quan Guo.
