import Foundation
import Darwin
import MountFSPrivileged

// Only Apple system executables are launched from a mutable application path.
// The root shell verifies a protected copy against this live process's CDHash
// before executing it. A path/hash check followed by exec of the source is unsafe.
let protectedExecutionGate = #"""
set -eu
source=$1
hash=$2
shift 2
case "$hash" in ''|*[!0-9a-f]*) exit 1;; esac
[ "${#hash}" -eq 40 ] || exit 1
secure_directory() {
    [ -d "$1" ] && [ ! -L "$1" ] || return 1
    metadata=$(/usr/bin/stat -f '%u %Lp' "$1")
    [ "${metadata%% *}" = 0 ] && [ "$((0${metadata#* } & 022))" -eq 0 ]
}
secure_file() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    metadata=$(/usr/bin/stat -f '%u %Lp %l' "$1")
    owner=${metadata%% *}
    remainder=${metadata#* }
    mode=${remainder%% *}
    [ "$owner" = 0 ] && [ "$((0$mode & 022))" -eq 0 ] && [ "${remainder#* }" = 1 ]
}
secure_directory /Library || exit 1
base=/Library/mountfs-authorizers
if [ ! -e "$base" ]; then /bin/mkdir -m 700 "$base" 2>/dev/null || true; fi
secure_directory "$base" || exit 1
directory="$base/$hash"
if [ ! -e "$directory" ]; then /bin/mkdir -m 700 "$directory" 2>/dev/null || true; fi
secure_directory "$directory" || exit 1
tool="$directory/mountfs-identity"
candidate=
trap '[ -z "$candidate" ] || /bin/rm -f "$candidate"' 0
if [ ! -e "$tool" ]; then
    candidate=$(/usr/bin/mktemp "$directory/.candidate.XXXXXXXX")
    # Private root storage and bounded copying prevent publication of an
    # attacker-swapped source. Only a fully verified image may become executable.
    /bin/dd if="$source" of="$candidate" bs=65536 count=1025 2>/dev/null
    /bin/chmod 700 "$candidate"
    /usr/bin/codesign --verify --strict -R "=cdhash H\"$hash\"" "$candidate"
    /bin/mv "$candidate" "$tool"
    candidate=
fi
secure_file "$tool" || exit 1
/usr/bin/codesign --verify --strict -R "=cdhash H\"$hash\"" "$tool"
exec "$tool" "$@"
"""#

final class RootBoundary {
    let source: String
    let hash: String
    private let driver: String?
    private let plan: String?
    init(driver: String? = nil) throws {
        source = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        guard let liveHash = runningExecutableCDHash() else { throw HelperError.invalid("Cannot pin the live authorization executable.") }
        hash = liveHash
        self.driver = driver
        if let driver {
            let data = try JSONSerialization.data(withJSONObject: driverApprovalPlan(driver), options: [.sortedKeys])
            guard data.count <= 65536, let value = String(data: data, encoding: .utf8) else { throw HelperError.invalid("Driver approval plan is too large.") }
            plan = value
        } else { plan = nil }
    }
    func command(_ arguments: [String]) throws -> [String] {
        let operation: [String]
        if arguments.count == 5, arguments[0] == CommandLine.arguments[0], arguments[1] == "--system-device-lock" {
            operation = Array(arguments.dropFirst())
        } else if let driver, let plan, arguments.first == driver {
            guard arguments.count == 5, arguments[1].hasPrefix("/dev/"),
                  let identity = mediaIdentity(String(arguments[1].dropFirst(5))) else { throw HelperError.invalid("Driver device identity is unavailable.") }
            operation = ["--approved-driver-run", plan, String(geteuid()), identity] + arguments
        } else { throw HelperError.invalid("Mutable executable is not an approved operation.") }
        return ["/bin/sh", "-c", protectedExecutionGate, "mountfs-protected-operation", source, hash] + operation
    }
}

func runApprovedDriver(_ args: [String]) -> Int32 {
    guard geteuid() == 0, args.count == 8, let uid = UInt32(args[1]), uid > 0,
          let data = args[0].data(using: .utf8), data.count <= 65536,
          let hashes = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
          ["/opt/homebrew/bin/ntfs-3g", "/usr/local/bin/ntfs-3g"].contains(args[3]),
          args[4].range(of: "^/dev/disk[0-9]+s[0-9]+(s[0-9]+)?$", options: .regularExpression) != nil,
          args[6] == "-o", args[7].contains(",uid=\(uid),"),
          args[7].range(of: "^rw,norecover,allow_other,default_permissions,uid=[0-9]+,gid=[0-9]+,umask=077,(local|backend=fskit)$", options: .regularExpression) != nil else { return 1 }
    let device = String(args[4].dropFirst(5))
    guard mediaIdentity(device) == args[2],
          args[5].range(of: "^/Volumes/mountfs\\.\(device)\\.[A-Za-z0-9]+$", options: .regularExpression) != nil,
          rootDirectory(args[5]), secureAncestors(args[5]),
          let state = mountState(device), (state["MountPoint"] as? String ?? "").isEmpty else { return 1 }
    let info = runTool("/usr/sbin/diskutil", ["info", "-plist", device])
    guard info.status == 0, let infoData = info.output.data(using: .utf8),
          let volume = (try? PropertyListSerialization.propertyList(from: infoData, format: nil)) as? [String: Any],
          volume["DeviceIdentifier"] as? String == device, volume["Internal"] as? Bool == false,
          volume["WholeDisk"] as? Bool == false, volume["FilesystemType"] as? String == "ntfs" else { return 1 }
    do {
        let driver = try approvedDriver(args[3], uid: uid, hashes: hashes)
        guard mediaIdentity(device) == args[2] else { return 1 }
        FileHandle.standardError.write(Data(("Protected NTFS driver: " + driver + "\nIf macOS denies device access, grant Full Disk Access to this protected driver path and retry.\n").utf8))
        let result = runTool("/usr/bin/sandbox-exec", ["-p", driverSandboxProfile, driver] + Array(args.dropFirst(4)), timeout: 60)
        if !result.output.isEmpty { FileHandle.standardError.write(Data((result.output + "\n").utf8)) }
        return result.status
    } catch { FileHandle.standardError.write(Data(("Approved driver refused: \(error)\n").utf8)); return 1 }
}
