#!/bin/bash
# Isolate executable mapping of an actual Mach-O library, without loading code.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE=$(mktemp -d "$HOME/Library/Caches/mountfs-map-test.XXXXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
printf 'int mountfs_fixture(void) { return 7; }\n' > "$FIXTURE/library.c"
clang -dynamiclib "$FIXTURE/library.c" -o "$FIXTURE/library.dylib"
clang -Wall -Wextra -Werror "$ROOT/tests/sandbox_mapping_test.c" -o "$FIXTURE/probe"
PROFILE=$(python3 - "$ROOT/Sources/MountFSHelper/DriverSnapshot.swift" <<'PY'
import json, sys
line = next(x for x in open(sys.argv[1]) if x.startswith('let driverSandboxProfile = '))
print(json.loads(line.split(' = ', 1)[1]))
PY
)
"$FIXTURE/probe" "$FIXTURE/library.dylib" -
# A pre-opened descriptor makes the previous read-only deny insufficient.
"$FIXTURE/probe" "$FIXTURE/library.dylib" '(version 1)(allow default)(deny file-read-data (subpath "/Users"))'
set +e
"$FIXTURE/probe" "$FIXTURE/library.dylib" "$PROFILE"
status=$?
set -e
[ "$status" -eq 1 ]
printf 'PASS actual executable mapping allowed by the old read-only deny and refused by the driver profile\n'
# Exercise the real root-owned lock store through independent tool processes.
HELPER="$ROOT/dist/mouNTFS.app/Contents/MacOS/mountfs-identity"
sudo "$HELPER" --system-device-lock acquire disk99999s9 ci-session-one
if sudo "$HELPER" --system-device-lock acquire disk99999s9 ci-session-two; then exit 1; fi
if sudo "$HELPER" --system-device-lock release disk99999s9 ci-session-two; then exit 1; fi
sudo "$HELPER" --system-device-lock release disk99999s9 ci-session-one
sudo "$HELPER" --system-device-lock acquire disk99999s9 ci-session-two
sudo "$HELPER" --system-device-lock release disk99999s9 ci-session-two
printf 'PASS independent privileged processes contend on the root-owned device lock and reject the wrong token\n'
