# Authorization and Touch ID design

Status: design recommendation, not shipped. Updated 2026-10-10.

## Current development build

0.2.11 retains the 0.2.8 authorization host, validated by the user after granting
Full Disk Access to the actual ntfs-3g executable. One compiled AppleScript lives
for one bounded mount transaction, including recovery and cleanup. It is not a
persistent root process and does not persist passwords. Exact interactive prompt
counts, cancellation and expiry still need physical-Mac validation.

Full Disk Access and administrator authorization are independent. Neither a
fingerprint result nor an administrator password grants ntfs-3g TCC access.

## Recommended next implementation

Use an opt-in, bundled SMAppService LaunchDaemon on macOS 13+, communicating over
XPC. Installation/approval is an explicit user setup action; service status and
unregister must be exposed in Settings. Preserve the current authorization path
when the helper is absent, denied or disabled. Never retry a possibly dispatched
mount through the fallback path: reconcile the current mount first.

The helper must authenticate the actual connecting process using its audit token
and an approved code-signing requirement; matching only a bundle ID or a PID is
insufficient. Stable app/helper signing is a prerequisite for a distributable
implementation; this repository currently produces ad-hoc development builds.

Expose typed requests for prepare, mount, recover, cleanup and eject, never an
arbitrary command or shell string. Resolve the driver from trusted configuration,
validate its ownership and permissions, and do not execute a caller-supplied
binary as root. Carry over partition identity checks, external NTFS filtering,
device locks, controlled directories and read-only recovery. Bound sessions to
one authenticated client, login session and live partition, with expiry and
replay rejection. Revalidate before each mutation. The UI's writable probe must
still run as the logged-in user, not root.

Use Authorization Services for administrator rights, verified on the privileged
side. The OS decides what authentication mechanisms are available; neither
SMAppService nor Authorization Services promises a Touch ID-only dialog on all
supported Macs. LocalAuthentication can be part of a separate user-presence
experience, but a client-supplied `authenticated=true` flag is not a privileged
authorization credential. A helper must not trust that flag as its security gate.

First prototype helper registration and the system authorization UI on the
reported Mac, with a harmless operation, before changing disk operations. If
native administrator authentication still requires a password, prioritize one-time
helper setup plus bounded authorized sessions, rather than advertising unsupported
fingerprint-only elevation. Do not change PAM, sudoers or the authorization database
to make the UI look like Touch ID support.

## Acceptance checks

- Registration, denial, disable, unregister and app replacement preserve a usable
  fallback. No automatic background service installation.
- An unapproved client, spoofed bundle ID, modified executable, replay or expired
  session cannot cause privileged work.
- One approved setup/transaction does not request administrator credentials for
  each individual subcommand. Test Touch ID availability, lockout, cancellation,
  password fallback, sleep/wake and a Mac without a fingerprint sensor.
- Device replacement, hot unplug, driver failure and late authorization cannot
  target another disk or trigger duplicate mounts; read-only recovery still works.
- ntfs-3g Full Disk Access is checked by a real device access attempt, not inferred
  from successful authentication. No hidden raw disk reads in a UI capability test.

## Primary references

- [LocalAuthentication](https://developer.apple.com/documentation/localauthentication):
  apps receive an authentication result, not biometric data or root privileges.
- [Authorization Services](https://developer.apple.com/documentation/security/authorization-services):
  system-managed authorization for privileged operations.
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
  and [register](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29):
  bundled service registration on macOS 13+ subject to user approval.
