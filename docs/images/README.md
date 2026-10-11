# Image provenance

## Native UI captures

These PNGs are native macOS window captures of the actual app menu and report UI,
using an isolated temporary build with sample volumes and an example log.

- UI source: commit ed7fe43cacd7fc9e07454ccf36a810b1683388b4, app version 0.3.4.
- Capture workflow: https://github.com/guoquan/mountfs/actions/runs/38034788885
- Generator: scripts/capture-docs.sh.
- Capture platform: GitHub macOS runner, arm64.
- Screens: read-only menu, writable menu, progress menu, example diagnostic report.

No disk scanning, mounting, helper registration or authorization was performed.
The screenshots demonstrate interface states, not physical-drive validation.
Both language editions use these images; the application UI is currently English.

Regenerate all captures together after relevant UI changes, inspect them and update
this provenance before committing. Do not overwrite examples with unredacted logs.

## Promotional artwork

`promo-hero.en.png`, `promo-hero.zh-CN.png`, `promo-share.en.png` and
`promo-share.zh-CN.png` form the bilingual landscape/square promotional set.
Created on 2026-10-10 with the built-in image-generation tool using the approved
light poster style and native sample captures above as references.

These are generated illustrations of the example interface, not pixel-exact native
captures and not evidence of physical-drive mounting. They retain the example UI's
version but add no separate release number. Both languages disclose driver/setup
requirements. See [promotional copy and visual rules](../PROMOTION.md) and
[generation prompts](promo-prompts.json).
