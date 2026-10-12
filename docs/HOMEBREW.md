# Homebrew installation (development channel)

The existing guoquan/mountfs repository also serves as an upstream Homebrew tap.
Use the explicit repository URL; the shorthand alone would look for a separate
homebrew-mountfs repository which does not exist.

```bash
brew tap guoquan/mountfs https://github.com/guoquan/mountfs
brew install --cask guoquan/mountfs/mountfs
brew install gromgit/fuse/ntfs-3g-mac
```

The cask installs mouNTFS.app into Applications and declares macFUSE as a
Homebrew dependency. The NTFS driver comes from the separate gromgit/fuse tap.
Follow macFUSE's approval and restart instructions; installation does not grant
macOS permissions. Current downloads support Apple Silicon and macOS 13+.
This is a third-party development tap, not official Homebrew Cask inclusion.
The app is ad-hoc signed and unnotarized. Homebrew preserves Gatekeeper checks;
first launch may be blocked. Homebrew installation does not repair helper signing.

本项目仓库同时作为 Homebrew tap 使用，必须带上完整仓库地址添加。
Cask 安装应用并安装 macFUSE 依赖；ntfs-3g 需另行通过第三方 tap 安装。
当前仅提供 Apple Silicon、macOS 13+ 的开发构建，仍为临时签名、未公证。
系统批准、重启和首次启动限制仍需用户处理；安装不会绕过 Gatekeeper。

## Upgrade

Quit mouNTFS before replacing the application:

```bash
brew update
brew upgrade --cask guoquan/mountfs/mountfs
```

Cask versions include the application build number (`0.3.4,19`), so a build-only
hotfix is recognized as an upgrade. The main release workflow updates the cask
from the latest published Release asset and its GitHub-provided SHA-256 digest.
An existing release rerun also attempts synchronization. Exact download URLs
and hashes are pinned; no mutable latest ZIP or unchecked checksum is used.
The updater refuses version downgrades, changes under the same version, malformed
release metadata and non-upstream asset URLs. Updates use GitHub's blob-SHA
concurrency check and the workflow's existing repository token, without new secrets.

## Uninstall

Eject active NTFS mounts and quit the app. If an older build registered the
permission helper, disable it in app Settings before uninstalling.

```bash
brew uninstall --cask guoquan/mountfs/mountfs
```

Uninstalling the app leaves shared drivers and protected driver generations intact.
It does not remove user data or force-unmount disks. No broad `zap` is supplied.

## Validation limits

CI parses the Ruby cask, resolves it through a local tap and downloads the actual
Release archive through Homebrew, verifying its pinned checksum. CI does not
launch the quarantined GUI, approve macFUSE or mount a physical NTFS disk.
First-launch, upgrade from a manually installed app and real-disk behavior require
physical-Mac verification. If Homebrew reports an existing app, quit it and move
the old app aside before retrying; do not force replacement while it is running.
