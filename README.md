# mouNTFS GitHub Pages redesign

This branch prepares the native-app homepage. It is based on `gh-pages` and retains
`.nojekyll` and the existing `CNAME` (`mountfs.sh`). It does not change the live site
until the branch is merged into the configured Pages branch.

## Structure

- `index.html`: English homepage.
- `zh-CN.html`: matching Simplified Chinese homepage with a language switch.
- `assets/`: local shared CSS, progressive enhancement JavaScript, SVG icon,
  native sample UI captures and bilingual social images.
- `scripts/build-site.py`: standard-library generator with aligned bilingual copy.

No Node build, remote font, analytics, GitHub widget or client framework is needed.
Both pages remain readable with JavaScript disabled. JavaScript adds keyboard-ready
state tabs and a copy-command button with a text-selection fallback.

## Browser QA

The **Homepage preview checks** workflow runs on this development branch and on
pull requests into `gh-pages`. It uses Playwright only for development QA and
uploads screenshots at 320, 390, 768 and 1440px, plus a JSON report. It tests both
languages, asset loading, horizontal overflow, state tabs, keyboard navigation,
copy commands, FAQ disclosure, language switching and basic content without JS.
This workflow does not deploy Pages or change the public domain.

To run locally with a browser available:

```bash
npm install --no-save --package-lock=false playwright@1.62.1
# Start the preview server first; optionally set CHROME_PATH to installed Chrome.
node scripts/check-site.mjs
```

## Preview and regenerate

```bash
python3 scripts/build-site.py
python3 -m http.server 8080
```

Open `/` or `/zh-CN.html`. The UI captures use sample drive data, not live devices;
the captions disclose this and the current English UI. Social images are generated
illustrations based on those captures, not proof of hardware validation.

## Coordinated promotion

1. Review the application development branch and this Pages branch together.
2. Merge the reviewed native-app work into `main` first.
3. Render production links with `CONTENT_REF=main python3 scripts/build-site.py`.
4. Check the `main` usage/roadmap/contributing links and a successful Checks run
   with a downloadable app artifact. Artifacts expire; a stable public release
   download is a separate future change. Download instructions currently require
   a signed-in GitHub account and describe ad-hoc, non-notarized development builds.
5. Recheck both page languages, mobile layouts, image loading, tabs and copy behavior.
6. Merge this Pages iteration into `gh-pages` after those checks. Preserve CNAME.
7. Confirm the actual configured GitHub Pages branch/path, deployment success and
   `https://mountfs.sh/` before announcing the live site.

Staging links currently point to `feat/mountfs-safe-core`, where the native-app docs
and app builds already exist. Do not silently present a development build as a
notarized release. The default kernel backend still requires compatible driver and
macOS permission setup; helper/Touch ID and experimental backends are not headline
features on this page.
