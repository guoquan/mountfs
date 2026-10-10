# Contributing

## Local development

App builds require macOS 13+ and Xcode Command Line Tools. From this checkout:

```bash
bash scripts/build-app.sh
open dist/mouNTFS.app
swift test
```

After building the native identity executable, the Bash 3.2-compatible core can also be used from this checkout:

```bash
bash mountfs.sh --list
bash mountfs.sh --diagnose
bash mountfs.sh --device disk4s1
bash mountfs.sh --cli --device disk4s1
```

`disk4s1` is an example; identify the actual partition before acting. Run as the
normal user: CLI mode requests sudo itself. The app/script do not install drivers.
Mounting requires the bundled or checkout-built native identity executable for
protected execution and system-wide locking. The script alone supports read-only
listing/diagnosis, not mounting. Exit codes: 0 success, 1 failure, 2 cancellation/invalid input,
130 interruption.

## Checks and boundaries

```bash
bash -n mountfs.sh
bash tests/core_tests.sh
bash tests/ntfs_identity_tests.sh
bash tests/media_identity_tests.sh
bash tests/mount_state_tests.sh
```

macOS CI adds real metadata parsing, Swift tests, signing pins and disposable root
launchd status checks. The helper test is intentionally restricted to GitHub Actions
runners; do not run it on a daily-use Mac. Automated tests do not establish NTFS
hardware compatibility, SMAppService approval or biometric behavior.
See [VALIDATION.md](docs/VALIDATION.md) for remaining physical tests and
[AUTHORIZATION.md](docs/AUTHORIZATION.md) for signing and privileged boundaries.

## Documentation structure

| Audience | English | Simplified Chinese |
|---|---|---|
| Project overview | README.md | README.zh-CN.md |
| Setup/use/troubleshooting | docs/USAGE.en.md | docs/USAGE.zh-CN.md |

Keep paired documents aligned in section order, functionality, commands, limitations,
image captions and links. Each pair has a language switch at the top. The application
UI is currently English; translated docs do not imply a localized UI.

Development documents are English-only: ROADMAP.md, CONTRIBUTING.md,
docs/AUTHORIZATION.md, docs/VALIDATION.md and docs/PROMOTION.md. The promotion guide
maintains aligned bilingual copy, artwork and brand rules. Explain user-visible behavior in user
docs; put implementation choices, experiments and specific test history in the
appropriate developer document. Planned work belongs in the roadmap.

## Native UI captures

```bash
bash scripts/capture-docs.sh docs/images
```

Requires a macOS GUI session and screen-capture access. The script copies the sources
into a temporary directory and builds the actual app with documentation-only sample
volumes and an example report. It reuses the production menu builder, branded header
and report window. It bypasses disk scanning, helper setup, driver execution and
authorization. No screenshot mode is added to the distributed app.

The **Documentation images** workflow produces the PNGs as an artifact. Review images
before checking them into docs/images. Both language versions use the same screenshots
and disclose sample data. Capture all four states together after relevant UI changes:
read-only, writable, progress and the diagnostic report. Do not present these images
as evidence of a successful real-drive mount or helper setup.

## Safety reviews

Focus on device identity, bounded authorization, exclusive write probes and
same-volume recovery. No forced NTFS recovery or clearing hibernation is supported.
Keep arbitrary shell commands and caller-selected executables out of the privileged
API. Distinguish simulation results from independently confirmed physical behavior.
