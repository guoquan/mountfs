# Optional permission helper and Touch ID

Current version: **0.3.4 development build**. This opt-in feature is not yet a
working user-validated authorization path. On the reported physical Mac,
registration repair returned `SMAppServiceErrorDomain / 1`, and the daemon still
terminated with `OS_REASON_CODESIGNING`. Its explicit spawn constraint was visible
in launchd state but did not resolve the failure. Investigation is paused pending
an Apple-issued signing environment. Use ordinary mounting while the helper is
not ready. Protected-driver mounting and biometric UI remain unvalidated.

## Setup and authority

The app registers a bundled SMAppService LaunchDaemon, subject to macOS approval.
Setup imports `system.privilege.admin` obtained in the user's process and verifies
it on the root side, with no interactive authorization in the daemon. No password
or authorization token is persisted. Only the approved login uid can begin mount
transactions after setup. The app exposes enable, disable and driver refresh.

The root daemon contains a build-time code requirement for the exact hardened
`mountfs-identity` client. NSXPCListener/NSXPCConnection enforce live peer signing
requirements; the client separately pins the bundled server. The main UI is not
itself an accepted daemon client. Pin generation and nested signing happen before
sealing the app, without re-signing the pinned executables afterward. Development
build updates can require disabling and re-enabling the service so a stale daemon
does not accept the new client. This is not stable Developer ID distribution.

## Protected driver

One-time administrator setup approves the selected existing Homebrew ntfs-3g.
The daemon copies that binary and its non-system Mach-O dependencies into a new
root-owned generation, rewrites load commands, removes resolved rpaths, and signs
the copied binaries. System libraries and protected macFUSE libraries remain in
place. The driver runs through a fixed sandbox profile that denies reads under
Homebrew and user-home prefixes, also blocking dynamically loaded reparse plugins
from mutable locations. If sandbox-exec is unavailable, helper mounting fails
without falling back; the user can disable the helper for the original flow. Unsupported dependency layouts fail setup rather than running mutable
Homebrew binaries persistently as root. Configuration and copy ancestors must
be root-owned and not group/world writable. No caller-selected executable path
is accepted by the mount API. Driver refresh requires administrator authorization.

These copies may require their own Full Disk Access. Existing Homebrew ntfs-3g
TCC approval is not assumed to cover another executable. The exact copy path is
reported by setup and transaction errors. Old generations are retained intentionally
to keep libraries available to existing mounted driver processes.

## Transaction boundary

XPC exposes status, authorized driver configuration, begin and a fixed operation
enum. There is no arbitrary shell or command argument endpoint. Begin validates
an external NTFS partition and pins its current IOMedia identity, original mount
point, caller uid/gid and protected driver. The daemon serializes requests, holds
a device lock, bounds sessions to five minutes, invokes the driver once and fixes
`rw,norecover,allow_other,default_permissions,uid,gid,umask` and backend options.

A connection-scoped client bridges the existing private plist request channel.
Both the unprivileged bridge and the daemon validate identity/state. No mutation
uses a timeout followed by fallback; a broken connection fails the operation.
The existing shell core verifies the writable kernel mount and performs an
exclusive create/write/remove probe as the login user. Only then does it commit
the helper transaction. An uncommitted disconnect/expiry attempts same-identity
read-only recovery, leaves unrelated mounts alone, and removes only its empty
controlled directory. A committed disconnect leaves the successful mount intact.

Helper absence selects the existing AppleScript path before starting a transaction.
Once helper execution starts, it does not silently retry the disk operation via
AppleScript. Whole-disk eject currently retains its separate existing confirmation
and diskutil path.

## Touch ID boundary

When the helper is ready, the app can use LocalAuthentication's native device-owner
confirmation before a mount. The setting defaults on; available biometry enables
the native Touch ID/password fallback. Unavailable biometry does not add a redundant
password prompt to already-approved helper operations. Cancellation stops before
starting the shell transaction. This is a UI user-presence confirmation, not an
administrator right or a daemon-trusted Boolean. The daemon's privileged authority
is the previous administrator setup plus the signed, approved-uid client and
restricted operation policy. A matching CLI client can use that restricted authority
without the UI's optional biometric confirmation.

## Validation

Shell simulations cover helper commit success and failed-commit read-only recovery
in addition to prior mount safety cases. Unprivileged daemon self-tests reject
writable storage, fake authorization data, unknown operations and missing media.
macOS CI checks exact client/server signing requirements and rejects the unrelated
UI executable as a root-service client. It also runs prior metadata, identity,
mount-table, private IPC and AppleScript policy tests.

Still requires physical-Mac testing: registration/approval, copied driver linkage
and macFUSE mount behavior, copied-driver Full Disk Access, Touch ID cancellation
and password fallback, helper replacement/disable, late connection loss, expiry,
hot unplug and the committed/uncommitted recovery distinction. CI temporarily
bootstraps the production helper as root on a disposable runner, but does not
register it with SMAppService, authorize driver setup or access an external NTFS drive.

## Primary references

- [LocalAuthentication](https://developer.apple.com/documentation/localauthentication)
- [Authorization Services](https://developer.apple.com/documentation/security/authorization-services)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [XPC peer signing requirements](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement%28_%3A%29)

0.3.2 uses `dispatchMain()` to keep the daemon alive after its listener resumes,
instead of relying on an otherwise empty Foundation run loop. Disposable macOS
CI bootstraps the production helper as root with an explicit Program path and
queries its status three times through the signed production XPC client. This
checks launchd startup, process lifetime, live peer pins and replies without
authorizing setup or touching a disk. It does not validate SMAppService approval
on a user's Mac. Helper startup/connection events are logged under
`net.guoquan.mountfs.helper` in Console.

The packaged launch daemon also pins the final signed helper using a binary
CDHash `SpawnConstraint` (enforced on macOS 14+). The disposable macOS CI test
retains the packaged constraint for root launchd status checks and verifies its
hash using positive/negative code-signing requirements. Direct bootstrap did not
enforce the plist constraint in our test. Actual SMAppService enforcement,
registration and system-generated BTM constraints remain untested by CI.


## Signing and setup procedure for future testing

Apple recommends signing the app and its embedded helper with the same Apple-issued
code-signing identity. Ad-hoc signatures can cause registration/approval persistence
problems. This is a recommended next diagnostic step, not proof of the exact failing
constraint or a guaranteed fix for the reported Mac.

Check available identities locally:

```bash
security find-identity -v -p codesigning
```

`0 valid identities found` means no usable identity was found by that query; the
project cannot supply one. Command Line Tools can build the ad-hoc app. Certificate
creation can be managed through a full Xcode installation and an Apple account;
Personal Team testing is distinct from Developer ID distribution and notarization.
Do not export or share private keys just to report identity availability.

With a suitable identity already installed, build from the project checkout:

```bash
MOUNTFS_SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)' bash scripts/build-app.sh
```

The script signs the client, builds/signs the helper, generates exact XPC pins and
the binary CDHash spawn constraint, then seals the app with the selected identity.
Re-signing a downloaded app afterward invalidates those pins. No certificate or
notarization credentials are included in the repository.

For a future controlled test, quit the old app, replace `/Applications/mouNTFS.app`,
and open it there. Choose Settings → Enable Permission Helper. If the service
actually reports `requiresApproval`, approve it in General → Login Items &
Extensions and return to setup. `SMAppServiceErrorDomain / 1` alone is not proof
that background approval is the only missing step. If no item appears or the
service cannot launch, preserve the registration/launch diagnostics rather than
repeatedly changing disk permissions.

Repair Permission Helper Registration unregisters only this service, refreshes
this app's Launch Services record and resubmits registration. It does not repair
invalid trust, guarantee removal of every stale BTM state or reset the global
background-item database. On the reported 0.3.4 build, repair did not restore a
working helper. Full Disk Access does not fix a demonstrated signing termination.

After service startup works, setup authorizes the protected driver copy. Its Full
Disk Access is separate from the Homebrew original. Refresh Protected NTFS Driver
imports an updated driver with administrator authorization. Disable Permission
Helper unregisters the service but retains driver generations and committed mounts.

A valid on-disk `codesign --verify --deep --strict` result does not establish that
macOS permits daemon startup. `launchctl print` displays some binary CDHash values
as blank text; that alone is not proof that the constraint contains an empty hash.
A crash report or relevant AMFI log is needed to identify the specific failing
constraint beyond the observed `OS_REASON_CODESIGNING` reason.

Additional primary references:

- [Apple signing guidance for SMAppService](https://developer.apple.com/forums/thread/799910)
- [Getting Started with SMAppService](https://developer.apple.com/forums/thread/802443)
- [Environment constraints](https://developer.apple.com/videos/play/wwdc2023/10266/)
- [Personal Team and developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)

## Review hardening: bounded tools and protected reads

Menu actions retain the IOMedia connection identity observed during the scan.
Mounts carry that identity into the shell core; mounts and ejection recheck it
immediately before launch, including after authorization or confirmation UI.
Missing or replaced media disable/refuse these actions rather than selecting a
new disk with a reused BSD identifier. This is a userspace check, not an atomic
kernel reservation against hot unplug during a system command.

Helper tools start in a dedicated process group with capped diagnostic output
and a monotonic deadline (normally 30 seconds; the driver gets up to 60 seconds,
bounded by the remaining transaction lifetime). Timeouts terminate the group,
escalate to SIGKILL and bound the reap wait. This lets serialized recovery and
expiry resume. Recovery can take additional bounded tool time after expiry.
If a kernel-stuck process cannot be reaped, the transaction refuses further
mutation and its device lock is retained until an administrator confirms all earlier operations ended and removes that specific stale lock. Detached
processes and actual kernel/driver timeout behavior still require physical-Mac
validation; successfully committed FUSE daemons are intentionally kept running.

Driver sources are opened by a no-follow descriptor walk and checked with fstat;
size is bounded while reading and metadata is rechecked afterward. A new driver
generation remains mode 0700 until dependency inspection, rewriting and signing
complete. Homebrew source content is still explicitly trusted by administrator
setup; this protects privileged reads and publication, not driver authenticity.
Authorization IPC requests have a five-minute maximum, an ended-session sentinel
and a macOS process-state query that rejects an unreaped zombie.


The default AppleScript path and opt-in root daemon share root-owned per-device
locks under `/Library/mountfs-locks`, across login users. The default
path acquires its lock after authorization and before preparing a mount directory.
Lock storage is opened through no-follow directory descriptors and must be owned
by root without group/world write access. Only the transaction's random ownership
token can release its lock. A collision fails before any disk mutation.

Crash leftovers are deliberately retained rather than inferred stale from a PID:
a driver can outlive its launching process, and PIDs can be reused. An administrator
should inspect the lock and verify that earlier mouNTFS/driver operations have
ended before removing that specific device lock. These locks survive daemon restarts and reboots; an inspected per-device
removal is required. Do not delete all locks while operations may be active.


### Execution-time validation in the default path

The unprivileged authorization host obtains its live CDHash from the kernel's
`csops(CS_OPS_CDHASH)` operation, rather than reading the current app signature
from a mutable path. The administrator shell launches Apple system tools only
until a candidate image in root-owned `/Library/mountfs-authorizers` storage has
passed strict signature validation against that hash. Every later invocation
checks that protected image again and executes it there; it never verifies one
file and then executes the mutable source. Source replacement before bootstrap
is refused; source replacement afterward cannot replace the protected image.

Before authorization, the default host inspects a private copy of the driver and
its non-system dependency graph and freezes their content hashes. The protected
authorizer re-reads those sources through no-follow descriptors, requires every
hash and graph entry to match, rewrites linkage, signs the copies and publishes
a root-owned generation only after writing its approval marker. A missing marker
prevents reuse of a partial generation. Existing approved generations avoid
reopening mutable sources at execution time. Execution uses the fixed sandbox
profile, including the executable-map denial. CLI mounts use the same protected
execution boundary after sudo authentication. The SMAppService flow remains
separately opt-in and retains its explicit administrator driver-setup policy.

The protected driver's Full Disk Access is a separate OS permission; a Homebrew
source grant may not cover the copy. Native CI fixtures test app-image replacement,
driver/dependency replacement and protected-copy reuse. They do not establish
real NTFS mounting or privacy-approval behavior on a physical Mac. Kernel-stuck
copy operations and exact OS authorization-cache behavior also require physical
validation.
