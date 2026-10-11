#!/bin/bash
# Disposable GitHub macOS runner only. Real launchd + pinned XPC status checks.
# No SMAppService registration, authorization prompt or disk mutation.
set -euo pipefail
[ "${GITHUB_ACTIONS:-}" = true ] || { printf 'Run only on a disposable GitHub Actions Mac.\n' >&2; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SERVICE=net.guoquan.mountfs.helper
HELPER="$ROOT/dist/mouNTFS.app/Contents/MacOS/mountfs-helper"
CLIENT="$ROOT/dist/mouNTFS.app/Contents/MacOS/mountfs-identity"
# Never replace or remove a service already present on the runner.
if sudo /bin/launchctl print "system/$SERVICE" >/dev/null 2>&1; then
    printf 'Test service already exists; refusing to replace it.\n' >&2
    exit 1
fi
WORK=$(mktemp -d)
LOADED=0
cleanup() {
    if [ "$LOADED" = 1 ]; then sudo /bin/launchctl bootout "system/$SERVICE" || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT
# Exercise the actual packaged constraint, changing only path resolution/logs.
python3 - "$ROOT/dist/mouNTFS.app/Contents/Library/LaunchDaemons/$SERVICE.plist" "$WORK/service.plist" "$HELPER" "$WORK" <<'PYPLIST'
import plistlib, sys, subprocess, re
with open(sys.argv[1], 'rb') as source:
    service = plistlib.load(source)
signature = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', sys.argv[3]],
                           capture_output=True, text=True, check=True).stderr
expected = bytes.fromhex(re.search(r'^CDHash=([0-9a-f]{40})$', signature, re.M)[1])
assert service['SpawnConstraint'] == {
    'signing-identifier': 'net.guoquan.mountfs.helper', 'cdhash': expected}
assert service.pop('BundleProgram') == 'Contents/MacOS/mountfs-helper'
service.update(Program=sys.argv[3], ProgramArguments=[sys.argv[3]],
               StandardErrorPath=sys.argv[4]+'/stderr', StandardOutPath=sys.argv[4]+'/stdout')
with open(sys.argv[2], 'wb') as output:
    plistlib.dump(service, output)
PYPLIST
sudo /usr/sbin/chown root:wheel "$WORK/service.plist"
sudo /bin/chmod 644 "$WORK/service.plist"
if ! sudo /bin/launchctl bootstrap system "$WORK/service.plist"; then
    sudo /usr/bin/log show --last 1m --style compact --predicate 'process == "launchd"' | tail -100
    exit 1
fi
LOADED=1
for attempt in 1 2 3; do
    printf 'XPC status check %s/3\n' "$attempt"
    if ! "$CLIENT" --helper-status > "$WORK/status"; then
        cat "$WORK/status"
        sudo /bin/launchctl print "system/$SERVICE" || true
        sudo cat "$WORK/stderr" || true
        exit 1
    fi
    [ "$(cat "$WORK/status")" = unconfigured ]
    # Run-loop early return/daemon exits must not be masked by status mocks.
    # The runner owns the diagnostic output; only launchctl needs root.
    # shellcheck disable=SC2024
    sudo /bin/launchctl print "system/$SERVICE" > "$WORK/state"
    grep -q 'state = running' "$WORK/state"
    sleep 1
done
printf 'PASS launchd root helper stays running and answers pinned XPC status requests\n'

# Direct bootstrap does not exercise SMAppService's SpawnConstraint handling.
# Check that the serialized pin selects precisely this signed helper, including
# a negative requirement check; do not call this a system launch rejection test.
python3 - "$WORK/service.plist" "$HELPER" <<'PYPIN'
import plistlib, sys, subprocess
with open(sys.argv[1], 'rb') as source:
    constraint = plistlib.load(source)['SpawnConstraint']
value = constraint['cdhash']
identifier = constraint['signing-identifier']
requirement = f'identifier "{identifier}" and cdhash H"{value.hex()}"'
subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '-R', '='+requirement, sys.argv[2]], check=True)
wrong = bytearray(value)
wrong[0] ^= 0xff
result = subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '-R',
                         '=cdhash H"'+wrong.hex()+'"', sys.argv[2]], capture_output=True)
assert result.returncode != 0, 'mismatched code hash unexpectedly accepted'
PYPIN
printf 'PASS packaged hash matches signed helper and wrong hash fails signature requirement\n'
