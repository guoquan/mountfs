#!/bin/bash
# Render the real app menu/output window using sample data in a throwaway build.
# No disk scan, authorization, driver execution or service registration is run.
set -euo pipefail
[ "$(uname -s)" = Darwin ] || { printf 'Requires a macOS GUI session.\n' >&2; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT=${1:-"$ROOT/docs/images"}
mkdir -p "$OUTPUT"
OUTPUT=$(cd "$OUTPUT" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/Package.swift" "$WORK/Package.swift"
cp -R "$ROOT/Sources" "$WORK/Sources"
cp -R "$ROOT/Tests" "$WORK/Tests"
python3 - "$WORK/Sources/MountFSApp/main.swift" <<'PYCAPTURE'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
# This modification exists only in the temporary documentation build.
s = s.replace('        refresh()\n        refreshHelperStatus()\n', '        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.captureDocumentationScene(0) }\n        return\n', 1)
# Keep the sample menu isolated from asynchronous disk scans during tracking.
s = s.replace('func menuWillOpen(_ menu: NSMenu) { menuTracking = true; refresh() }',
              'func menuWillOpen(_ menu: NSMenu) { menuTracking = true }')
method = r'''
    private func captureDocumentationScene(_ index: Int) {
        let names = ["menu-readonly", "menu-writable", "menu-progress", "diagnostics"]
        guard index < names.count else { NSApp.terminate(nil); return }
        let output = ProcessInfo.processInfo.environment["MOUNTFS_DOC_OUTPUT"]!
        volumes = [Volume(device: "disk9s1", mediaIdentity: "iomedia:900:901:1048576", name: "Travel Drive", mountPoint: "/Volumes/Travel Drive", readOnly: index != 1)]
        busy = index == 2
        status = index == 1 ? "Demo · Write access verified" : (busy ? "Demo · Enabling write access…" : "Demo · 1 external NTFS partition")
        helperReady = false
        helperStatus = "Not enabled"
        rebuildMenu()
        if index == 3 {
            showOutput(title: "Example operation log", text: "Documentation example — sample disk data\n\n[1/4] Preparing mount directory…\n[2/4] Unmounting volume…\n[3/4] Mounting with ntfs-3g (kernel)…\n[4/4] Verifying write access as the current user…\n\nWrite access verified: /Volumes/Travel Drive\n\nThis screenshot demonstrates the report window.\nNo disk operation was performed to create it.")
        }
        let timer = Timer(timeInterval: 1, repeats: false) { _ in
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let candidates = windows.filter { window in
                guard (window[kCGWindowOwnerPID as String] as? Int) == Int(getpid()),
                      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
                else { return false }
                return (bounds["Width"] ?? 0) >= 200 && (bounds["Height"] ?? 0) > 150
            }
            guard let window = candidates.first,
                  let number = window[kCGWindowNumber as String] as? Int else {
                fputs("No visible documentation window: \(windows)\n", stderr)
                exit(1)
            }
            let result = runCommand("/usr/sbin/screencapture", ["-x", "-l", String(number), output + "/" + names[index] + ".png"])
            guard result.status == 0 else { fputs(result.text, stderr); exit(1) }
            self.statusItem.menu?.cancelTracking()
            self.outputWindow?.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.captureDocumentationScene(index + 1) }
        }
        RunLoop.main.add(timer, forMode: .common)
        if index != 3 {
            NSApp.activate(ignoringOtherApps: true)
            statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 200, y: 700), in: nil)
        }
    }
'''
s = s.replace('    @objc private func quitApp()', method + '\n    @objc private func quitApp()')
s = s.replace('?? "0.3.3"', '?? "0.3.4"')
p.write_text(s)
PYCAPTURE
swift build --package-path "$WORK" -c release --product MountFS
BIN=$(swift build --package-path "$WORK" -c release --show-bin-path)
MOUNTFS_DOC_OUTPUT="$OUTPUT" "$BIN/MountFS"
for scene in menu-readonly menu-writable menu-progress diagnostics; do test -s "$OUTPUT/$scene.png"; done
printf 'Captured native UI with sample data: %s\n' "$OUTPUT"
