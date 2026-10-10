# mouNTFS roadmap

Build on the current menu bar mounting flow: first consolidate everyday usability,
then reduce authorization friction, and finally prepare a polished public release.
Stages are ordered without promised dates or version numbers. Features enter the
user guide after their acceptance criteria have been met.

## Stage 1 — Everyday usability

- Improve drive-state refresh, progress and completion feedback.
- Refine menu hierarchy, icons, light/dark appearance and actionable errors.
- Keep user documentation focused on setup, mounting, eject and common problems;
  maintain English and Simplified Chinese versions together.
- Test common drive/OS/driver combinations, failure recovery and safe eject.

Acceptance: the existing flow works consistently in the target environments and
users can understand the current state, result and next step after failure.

## Stage 2 — Reliable permission service

Goal: one service setup followed by fewer administrator password requests during mounting.

- Use a consistent Apple-issued signing identity and validate app/helper
  registration, background approval and startup.
- Validate replacement updates, reconnection, disabling and driver refresh.
- Test the protected driver's permissions, dependencies and actual mounting.
- Retain ordinary mounting and clearly handle an unavailable service.

Acceptance: first setup, restart, replacement update and mounting pass on physical
Macs before recommending the helper as the normal authorization flow.

Status: an experimental implementation exists; acceptance criteria are not met.
Continue when suitable signing and physical testing are available. Specific
failures belong in the [validation record](docs/VALIDATION.md) and
[authorization architecture](docs/AUTHORIZATION.md), not everyday usage instructions.

## Stage 3 — Touch ID and authorization interaction

Depends on a reliable permission service from Stage 2.

- Provide native Touch ID confirmation on supported Macs.
- Validate password fallback, cancellation and devices without biometry.
- Distinguish administrator approval for setup from user confirmation of an operation.
- Reduce repeated confirmation while retaining understandable preferences.

Acceptance: successful, cancelled and fallback flows pass on real devices.
Biometric confirmation must not be described as replacing every system permission.

## Stage 4 — First-run guidance and public release

- Guide driver installation, system approval and disk privacy permission setup.
- Complete Chinese UI localization, menu polish and diagnostic report usability.
- Complete Developer ID signing, notarization and clean-Mac download testing.
- Document compatibility, versioned downloads and checksums; align website and repository.
- Keep the app named `mouNTFS.app` and include versions in download archive names.

Acceptance: users can install, update and operate the app from its documentation;
publicly advertised features have corresponding validation evidence.

## Further exploration — FSKit

Test FSKit with compatible OS/driver combinations and evaluate its installation
experience. Keep it experimental rather than replacing the default backend until
real-drive writing, identity checks, recovery and eject have been validated.
