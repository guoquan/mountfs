#!/bin/bash
# Disposable macOS CI only. No raw-device access or mounts.
set -euo pipefail
[ "${GITHUB_ACTIONS:-}" = true ] || exit 1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLIENT="$ROOT/dist/mouNTFS.app/Contents/MacOS/mountfs-identity"
WORK=$(mktemp -d)
DRIVER_SOURCE=/opt/homebrew/bin/ntfs-3g
[ ! -e "$DRIVER_SOURCE" ] && [ ! -L "$DRIVER_SOURCE" ] || { echo 'Driver fixture would replace an existing installation'; exit 1; }
FIXTURE=$(mktemp -d /opt/homebrew/Cellar/mountfs-review-test.XXXXXXXX)
GENERATION=
cleanup_boundary() {
    rm -f "$DRIVER_SOURCE"
    rm -rf "$WORK" "$FIXTURE"
    if [ -n "$GENERATION" ]; then sudo rm -rf "$GENERATION"; fi
}
trap cleanup_boundary EXIT
cp "$CLIENT" "$WORK/client"
"$WORK/client" --root-boundary-args acquire disk99999s8 ci-boundary-token > "$WORK/command.json"
# Prepare the signed live-image requirement, then replace its source before root runs.
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$WORK/attacker-ran" > "$WORK/client"
chmod +x "$WORK/client"
python3 - "$WORK/command.json" <<'PY'
import json, subprocess, sys
args = json.load(open(sys.argv[1]))
result = subprocess.run(['sudo', '-n', '--', *args], check=False)
assert result.returncode != 0, 'Replaced executable was not refused'
PY
[ ! -e "$WORK/attacker-ran" ]
cp "$CLIENT" "$WORK/client"
python3 - "$WORK/command.json" <<'PY'
import json, subprocess, sys
subprocess.run(['sudo', '-n', '--', *json.load(open(sys.argv[1]))], check=True)
PY
"$WORK/client" --root-boundary-args release disk99999s8 ci-boundary-token > "$WORK/release.json"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$WORK/attacker-ran" > "$WORK/client"
python3 - "$WORK/release.json" <<'PY'
import json, subprocess, sys
subprocess.run(['sudo', '-n', '--', *json.load(open(sys.argv[1]))], check=True)
PY
[ ! -e "$WORK/attacker-ran" ]
echo 'PASS source replacement is refused before bootstrap; cached root-owned image survives later app replacement'
# A real Mach-O dependency graph, inspected and pinned while unprivileged.
printf 'int review_value(void) { return 7; }\n' > "$WORK/library.c"
clang -dynamiclib -Wl,-headerpad_max_install_names "$WORK/library.c" -o "$FIXTURE/library.dylib"
printf '#include <stdio.h>\nextern int review_value(void);\nint main(void) { printf("%%d\\n", review_value()); return 0; }\n' > "$WORK/driver.c"
clang -Wl,-headerpad_max_install_names "$WORK/driver.c" "$FIXTURE/library.dylib" -o "$FIXTURE/ntfs-3g"
ln -s "$FIXTURE/ntfs-3g" "$DRIVER_SOURCE"
"$CLIENT" --driver-approval-plan "$DRIVER_SOURCE" > "$WORK/plan.json"
cp "$FIXTURE/ntfs-3g" "$WORK/original-driver"
cp "$FIXTURE/library.dylib" "$WORK/original-library"
# Use the root-owned verified authorizer, never sudo a mutable source executable.
HASH=$(/usr/bin/codesign -d --verbose=4 "$CLIENT" 2>&1 | sed -n 's/^CDHash=//p')
PROTECTED=/Library/mountfs-authorizers/$HASH/mountfs-identity
PLAN=$(cat "$WORK/plan.json")
UID_NUMBER=$(id -u)
printf 'int main(void) { return 13; }\n' > "$WORK/replacement.c"
clang "$WORK/replacement.c" -o "$FIXTURE/ntfs-3g"
if sudo "$PROTECTED" --prepare-approved-driver "$PLAN" "$UID_NUMBER" "$DRIVER_SOURCE"; then exit 1; fi
cp "$WORK/original-driver" "$FIXTURE/ntfs-3g"
printf 'int review_value(void) { return 13; }\n' > "$WORK/library.c"
clang -dynamiclib "$WORK/library.c" -o "$FIXTURE/library.dylib"
if sudo "$PROTECTED" --prepare-approved-driver "$PLAN" "$UID_NUMBER" "$DRIVER_SOURCE"; then exit 1; fi
cp "$WORK/original-library" "$FIXTURE/library.dylib"
APPROVED=$(sudo "$PROTECTED" --prepare-approved-driver "$PLAN" "$UID_NUMBER" "$DRIVER_SOURCE")
GENERATION=${APPROVED%/*}
[ "$(sudo "$APPROVED")" = 7 ]
clang "$WORK/replacement.c" -o "$FIXTURE/ntfs-3g"
printf 'int review_value(void) { return 13; }\n' > "$WORK/library.c"
clang -dynamiclib "$WORK/library.c" -o "$FIXTURE/library.dylib"
[ "$(sudo "$PROTECTED" --prepare-approved-driver "$PLAN" "$UID_NUMBER" "$DRIVER_SOURCE")" = "$APPROVED" ]
[ "$(sudo "$APPROVED")" = 7 ]
echo 'PASS replaced driver and dependency refused; published protected snapshot executes original dependency bytes after source replacement'
