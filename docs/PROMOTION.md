# Promotional copy and artwork

This is the English-only maintenance guide for the bilingual promotional set.
It records reusable copy and visual rules for README, sharing and a later website
update. It does not change the website or advertise planned features as available.

## Core copy

| Use | English | Simplified Chinese |
|---|---|---|
| Main headline | Write to NTFS. On your Mac. | Mac，也能写入 NTFS。 |
| Supporting line | No reformatting. Enable writing, then copy files in Finder. | 无需格式化。启用写入，继续在 Finder 中使用。 |
| Short descriptor | A free, open-source NTFS menu bar app for Mac. | 免费开源的 Mac NTFS 菜单栏工具。 |
| Benefit 1 | Free & open source | 免费开源 |
| Benefit 2 | Keep NTFS | 保留 NTFS 格式 |
| Benefit 3 | Menu bar access | 菜单栏操作 |
| Setup note | Requires macFUSE, ntfs-3g and macOS permissions. | 需先安装 macFUSE 与 ntfs-3g，并完成系统授权。 |
| Illustration label | Example interface | 示例界面 |
| Primary action | Get started | 查看使用说明 |
| Secondary action | View source | 查看源代码 |

## Product description

### English

mouNTFS is a free, open-source Mac menu bar app for external NTFS drives.
Keep your drive's NTFS format, enable writing from the menu bar, then copy and edit
files in Finder. When finished, close files and eject the drive from the app.
Initial setup requires compatible macFUSE and ntfs-3g installations and macOS
permissions. Current downloads are development builds, ad-hoc signed and not notarized.

### Simplified Chinese

mouNTFS 是免费开源的 Mac 菜单栏工具，让外置 NTFS 磁盘在 Mac 上也能写入。
保留磁盘原有的 NTFS 格式，从菜单栏启用写入，继续在 Finder 中拷贝和编辑文件；
用完关闭文件，再从应用中弹出磁盘。首次使用需安装兼容的 macFUSE 和 ntfs-3g，
并完成 macOS 权限配置。当前下载为开发构建，使用 ad-hoc 签名，尚未公证。

## Sharing copy

### English

An NTFS drive you can read, but can't copy files onto?

mouNTFS lets you enable writing from your Mac's menu bar and continue in Finder,
without reformatting the drive. Free and open source.

Install macFUSE and ntfs-3g and complete macOS permissions first.
Current downloads are ad-hoc signed development builds, not notarized releases.

Setup: https://github.com/guoquan/mountfs/blob/main/docs/USAGE.en.md

### Simplified Chinese

NTFS 硬盘里的文件能看，新文件却拷不进去？

mouNTFS 让你从 Mac 菜单栏启用写入，继续在 Finder 中使用，无需格式化磁盘。
免费开源。

首次使用需先安装 macFUSE 和 ntfs-3g，并完成 macOS 权限配置。
当前提供开发构建，使用 ad-hoc 签名，尚未公证。

使用说明：https://github.com/guoquan/mountfs/blob/main/docs/USAGE.zh-CN.md

## Human–AI project story

Keep this identity visible in the project story, credits or a development update,
separate from the primary product proposition. The original collaboration slogans
remain in both README editions. A short optional line is:

- English: Built with AI. Shaped by humans.
- Simplified Chinese: 与 AI 一起开发，由人类设计、审查和测试。

## Asset inventory

| Asset | English | Simplified Chinese | Intended use |
|---|---|---|---|
| Landscape hero | [PNG](images/promo-hero.en.png) | [PNG](images/promo-hero.zh-CN.png) | README, wide product introduction |
| Square share card | [PNG](images/promo-share.en.png) | [PNG](images/promo-share.zh-CN.png) | Social sharing, compact project introduction |

The matching language hero is embedded in each README. Native UI captures remain
available separately and are the authoritative interface examples.

[The reusable wordmark](images/wordmark.svg) provides a transparent vector version
for future layouts. Hero pills may shorten “Keep NTFS” to “No reformatting” in the
Chinese layout; they describe the same benefit. Full copy is aligned above.

## Visual and editorial rules

- Use a light off-white canvas, blue-violet accents, navy text, soft lavender forms
  and restrained shadows. Keep whitespace and clear typography.
- Spell the wordmark `mouNTFS`: `mouNT` shares one blue-violet treatment; `FS` is
  dark navy. The overlapping `NT` stays uppercase. Do not change it to `mountNTFS`.
  The standalone `mN` symbol retains the existing app identity.
- Explain the task: write to an existing external NTFS drive and use Finder.
  Free/open source is a product fact, not proof of uniqueness.
- Keep primary copy and benefit order aligned across languages; adapt line breaks
  to fit each language. The app UI stays English until localization is implemented.
- Do not add a release/version badge to promotional artwork. Versions inside UI
  examples may remain. A new release alone does not require new artwork; update it
  when the visible UI or the depicted behavior changes.
- Retain a legible setup note and example-interface label on every shared card.
  Do not promise installation without configuration, automatic writing, fewer
  password prompts, Touch ID, a production-ready helper or a notarized release.
- Do not advertise speed or safety superiority without comparative evidence.
  Verification and diagnostics belong in supporting documentation, not headline pills.
- Keep screenshots and illustration provenance distinct. Generated artwork is not
  a pixel-exact native capture or evidence of hardware validation.

## Generation and review

The raster artwork was made with the built-in image-generation tool. Prompts are
recorded in [the generation manifest](images/promo-prompts.json). Style references
were the previously approved light posters; app-menu references were the native
sample captures in this directory. Review spelling, wordmark, UI text, captions,
copy alignment, margins and rendering at small sizes before reuse.

No disk operations were performed to produce the artwork. Dependencies, permissions
and current release status must remain visible in accompanying download/setup copy.
