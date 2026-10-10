# Validation record — 0.3.4 development build

Status: **limited user-reported ordinary mounting success; optional helper startup
failed on the reported Mac; wider physical-drive validation pending.** CI and user
reports are separate evidence. Use disposable test drives for additional tests.

## Physical-Mac reports, 2026-10-10

Reported environment: macOS 27.0.1, arm64, kernel backend, external NTFS volume LMT,
missing DiskUUID/VolumeUUID, Homebrew ntfs-3g at `/opt/homebrew/bin/ntfs-3g`.
Exact macFUSE and ntfs-3g versions were not captured. These results were reported
by the user and were not independently reproduced in a lab.

| Observation | Evidence and limit |
|---|---|
| Ordinary mounting reached writable verification | Supplied log showed a writable kernel mount at the expected path on the second verification attempt and successful current-user write verification |
| 0.2.8 ordinary authorization flow works on retry | User confirmed success after granting ntfs-3g Full Disk Access; mouNTFS Full Disk Access could be disabled |
| App Full Disk Access alone did not solve device EPERM | Device-open denial persisted until driver permission was granted; the appended unsafe-state hint did not establish hibernation |
| Old macFUSE rejected the OS version | Driver upgrade and restart allowed testing to proceed; exact upgraded driver version was not recorded |
| Earlier helper launch failed | Logs showed spawn failure / EX_CONFIG and subsequently OS_REASON_CODESIGNING despite a valid on-disk signature |
| 0.3.4 repair/setup still failed | Repair returned SMAppServiceErrorDomain / 1, service status 0 at that point; subsequent launch state showed parent build 18 and a code-signing termination |
| Explicit 0.3.4 SpawnConstraint did not fix startup | Constraint was present in launchd state; helper still did not reply and last exit reason remained OS_REASON_CODESIGNING |
| Signing investigation paused | App/helper were ad-hoc signed without TeamIdentifier; local identity query found no valid identities and the Mac had only Command Line Tools |

The successful ordinary flow is the AppleScript authorization host, not the root
helper. 0.2.10 restored that authorization-session implementation after the user's
0.2.8 confirmation. Success in that earlier version does not establish a complete
0.3.4 real-drive compatibility matrix. The root helper's protected-driver setup,
mounting and Touch ID confirmation have not completed physical-Mac validation.

## Automated checks

| Check | What it establishes | What it does not establish |
|---|---|---|
| Shell simulations | Cancellation, busy disk, driver failure, false success, probe failure, replacement/identity refusal, helper commit handling and existing-file protection in modeled cases | Actual driver/kernel behavior and hot-plug timing |
| Boot-record fixtures | Validation, fingerprint pinning, aligned dd/od pipeline and failure propagation on regular-file fixtures | Raw-device TCC access or hardware alignment behavior |
| IOMedia tests | Modeled replacement/source pinning plus actual repeated metadata queries on the runner | NTFS connection stability across every real mount/unplug scenario |
| macOS plist and Swift tests | Actual diskutil schema parsing and conservative metadata handling | Driver compatibility on an external NTFS volume |
| Kernel mount-table tests | Source/path/flags queries and missing-mount rejection on the runner | Real external-drive write access |
| Signing/IPC tests | Exact client/server pins and unrelated-client rejection; unprivileged policy/driver snapshot tests | SMAppService approval or privileged driver setup |
| Disposable root launchd status checks | Production helper remains alive and answers three pinned XPC requests | SMAppService/BTM registration and copied-driver mounting |
| Packaged SpawnConstraint checks | Serialized hash matches the signed helper; a changed hash fails a code-signing requirement | OS enforcement of that plist constraint through SMAppService; direct bootstrap did not enforce it in the CI experiment |
| App packaging | Versioned download archive, stable mouNTFS.app name, icon assets and on-disk signature verification | Finder/menu legibility, Gatekeeper acceptance or notarization |

CI temporarily bootstraps a root service only on disposable macOS Actions runners.
It does not authorize driver setup or access an external NTFS drive. Positive
launchctl bootstrap tests cannot be substituted for the failed real SMAppService
registration path.

## Remaining physical test matrix

Record application commit/version, macOS build, architecture, macFUSE/ntfs-3g
versions, backend, identity source, driver path/permissions and outcome for each run.

| Scenario | Required observation | Current state |
|---|---|---|
| Clean NTFS, kernel, Intel/Apple Silicon | Writable mount, exclusive probe, Finder access | Limited Apple Silicon user report; Intel and broader combinations pending |
| UUID-less MBR/GPT partitions | Stable pinned identity through unmount/remount | UUID-less user report; broader layouts pending |
| Compatible FSKit | Mount, identity, write and eject | Pending |
| Unicode/quotes/spaces in volume names | Correct selection and argument handling | Simulations/quoting tests only; real-drive check pending |
| Cancel confirmation/authorization | No mutation, or explicit recovery outcome | Simulations only |
| Busy unmount | No force; original mount retained | Simulation only |
| Failed driver/false success/probe failure | Same-volume read-only recovery, clear failure if impossible | User logs show recovery messages; independent state confirmation and full matrix pending |
| Hibernated/unclean NTFS | No forced write or hibernation removal | Real-drive test pending |
| Unplug/replace during transaction | No recovery against a replacement identity | Simulation only; hardware race tests pending |
| Existing .write_test and other files | Contents untouched; exclusive probe removed | Filesystem fixture/simulation; real-drive test pending |
| Concurrent operations/signals | Refusal or bounded best-effort cleanup | Simulation only; process/death timing pending |
| Multi-partition eject | Confirmed whole-disk eject, no partial/busy ambiguity | Pending |
| Native menu/icon light and dark modes | Readable state and consistent app branding | Packaging checked; systematic visual test pending |
| Helper registration and replacement | Service starts after approval and answers current client | Failed on reported ad-hoc builds; Apple-issued signing test pending |
| Protected driver setup/FDA/linkage | Root-owned approved copy mounts correctly | Pending |
| Touch ID/password/cancellation | Correct native confirmation and cancellation boundary | Pending |
| Helper disconnect/expiry | Uncommitted same-identity recovery; committed mount retained | Policy tests only; real-drive check pending |

## Identity and recovery limits

Device numbers and names are not stable identity fallbacks. The app can use a live
IOMedia connection identity (partition ID, parent media ID and size) without raw
filesystem reads; standalone use can retain a validated boot-record fallback.
Identity source is pinned for the transaction. A cloned UUID/boot record is not
hardware authentication. Missing identity or a changed/disappeared device stops
further targeting rather than switching sources.

Recovery is best-effort and can fail through busy mounts, cancellation or OS errors.
Signals cannot cover SIGKILL, power loss or every hot-plug race. Test recovery state
independently in Disk Utility/mount queries, not just from completion text.

## Before public distribution

- Complete real-drive tests for the intended OS/driver/backend combinations.
- Resolve helper signing/registration before describing it as a working feature.
- Validate Touch ID and protected-driver Full Disk Access/linkage separately.
- Complete Developer ID signing and notarization; test downloads on a clean Mac.
- Establish published versioned artifacts/checksums and update the separate website
  deliberately; this development branch has not updated its download endpoint.
- Review localization, first-run guidance and native visual appearance.

See [authorization details](AUTHORIZATION.md) and [中文使用说明](USAGE.zh-CN.md).
