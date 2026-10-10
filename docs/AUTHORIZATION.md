# Optional permission helper and Touch ID

0.3.0 implements this as an opt-in development feature. Physical-Mac validation
of registration, protected driver mounting and biometric UI is pending.

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
place. Unsupported dependency layouts fail setup rather than running mutable
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
hot unplug and the committed/uncommitted recovery distinction. CI does not install
a root daemon or access an external NTFS drive.

## Primary references

- [LocalAuthentication](https://developer.apple.com/documentation/localauthentication)
- [Authorization Services](https://developer.apple.com/documentation/security/authorization-services)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [XPC peer signing requirements](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement%28_%3A%29)
