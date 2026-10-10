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
python3 - "$WORK/service.plist" "$HELPER" "$SERVICE" "$WORK" <<'PYPLIST'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'Label': sys.argv[3], 'Program': sys.argv[2],
                  'MachServices': {sys.argv[3]: True},
                  'StandardErrorPath': sys.argv[4]+'/stderr',
                  'StandardOutPath': sys.argv[4]+'/stdout'}, f)
PYPLIST
sudo /bin/launchctl bootstrap system "$WORK/service.plist"
LOADED=1
for attempt in 1 2 3; do
    if ! "$CLIENT" --helper-status > "$WORK/status"; then
        cat "$WORK/status"
        sudo /bin/launchctl print "system/$SERVICE" || true
        sudo cat "$WORK/stderr" || true
        exit 1
    fi
    [ "$(cat "$WORK/status")" = unconfigured ]
    # Run-loop early return/daemon exits must not be masked by status mocks.
    sudo /bin/launchctl print "system/$SERVICE" > "$WORK/state"
    grep -q 'state = running' "$WORK/state"
    sleep 1
done
printf 'PASS launchd root helper stays running and answers pinned XPC status requests\n'
