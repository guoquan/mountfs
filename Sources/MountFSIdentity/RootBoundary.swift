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
    func command(_ arguments: [String], deadline: TimeInterval? = nil, device: String? = nil, identity: String? = nil) throws -> [String] {
        var operation: [String]
        if arguments.count == 5, arguments[0] == CommandLine.arguments[0], arguments[1] == "--system-device-lock" {
            operation = Array(arguments.dropFirst())
        } else if let driver, let plan, arguments.first == driver {
            guard arguments.count == 5, arguments[1].hasPrefix("/dev/"),
                  let identity = mediaIdentity(String(arguments[1].dropFirst(5))) else { throw HelperError.invalid("Driver device identity is unavailable.") }
            operation = ["--approved-driver-run", plan, String(geteuid()), identity] + arguments
        } else if let device, let identity, authorizedSystemArguments(arguments, device: device) {
            operation = ["--authorized-system-run", device, identity] + arguments
        } else { throw HelperError.invalid("Executable is not an approved operation.") }
        if let deadline { operation = ["--bounded-authorized-operation", String(deadline)] + operation }
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
        return confirmedAuthorizedToolStatus(result.status)
    } catch { FileHandle.standardError.write(Data(("Approved driver refused: \(error)\n").utf8)); return 1 }
}


// Reserve 124 at the wrapper boundary for the wrapper's own deadline.
// Inner 124 already confirms process-group disappearance and is an ordinary
// operation failure; inner 125 must keep its lock-retaining meaning.
func confirmedAuthorizedToolStatus(_ status: Int32) -> Int32 { status == 124 ? 1 : status }

func authorizedSystemArguments(_ args: [String], device: String) -> Bool {
    guard device.range(of: "^disk[0-9]+s[0-9]+(s[0-9]+)?$", options: .regularExpression) != nil else { return false }
    if args == ["/usr/sbin/diskutil", "unmount", device] || args == ["/usr/sbin/diskutil", "mount", "readOnly", device] { return true }
    if args == ["/usr/bin/mktemp", "-d", "/Volumes/mountfs.\(device).XXXXXXXX"] { return true }
    return args.count == 2 && args[0] == "/bin/rmdir" &&
        args[1].range(of: "^/Volumes/mountfs\\.\(device)\\.[A-Za-z0-9]+$", options: .regularExpression) != nil
}

// The wrapper may have launched descendants with their own process groups.
// Its timeout therefore cannot establish that privileged work has stopped.
func executeBeforeDeadline(_ path: String, _ args: [String], deadline: TimeInterval) -> (Int32, Data) {
    let remaining = deadline - ProcessInfo.processInfo.systemUptime
    guard deadline.isFinite, remaining > 0, remaining <= 420 else { return (1, Data("Authorization operation deadline expired or invalid.\n".utf8)) }
    let result = boundedTool(path, args, timeout: remaining)
    if result.0 == 124 {
        return (125, result.1 + Data("\nAuthorized work exceeded its deadline; descendant completion is uncertain and the device lock must be retained.\n".utf8))
    }
    return result
}

func runBoundedAuthorization(_ args: [String]) -> Int32 {
    guard geteuid() == 0, args.count >= 2, let deadline = TimeInterval(args[0]),
          ["--approved-driver-run", "--system-device-lock", "--authorized-system-run"].contains(args[1]),
          rootFile(CommandLine.arguments[0]), secureAncestors(CommandLine.arguments[0]) else { return 1 }
    let result = executeBeforeDeadline(CommandLine.arguments[0], Array(args.dropFirst()), deadline: deadline)
    if !result.1.isEmpty { (result.0 == 0 ? FileHandle.standardOutput : FileHandle.standardError).write(result.1) }
    return result.0
}

func runAuthorizedSystemCommand(_ args: [String]) -> Int32 {
    guard geteuid() == 0, args.count >= 4 else { return 1 }
    let device = args[0], identity = args[1], command = Array(args.dropFirst(2))
    guard authorizedSystemArguments(command, device: device), mediaIdentity(device) == identity,
          let state = mountState(device) else { return 1 }
    if command.first == "/bin/rmdir" {
        guard rootDirectory(command[1]), secureAncestors(command[1]), state["MountPoint"] as? String != command[1] else { return 1 }
    }
    if command == ["/usr/sbin/diskutil", "mount", "readOnly", device] {
        guard (state["MountPoint"] as? String ?? "").isEmpty else { return 1 }
    }
    guard mediaIdentity(device) == identity else { return 1 }
    let result = runTool(command[0], Array(command.dropFirst()))
    if !result.output.isEmpty { (result.status == 0 ? FileHandle.standardOutput : FileHandle.standardError).write(Data(result.output.utf8)) }
    return confirmedAuthorizedToolStatus(result.status)
}

func authorizationDeadlineSelfTest() -> Bool {
    let start = ProcessInfo.processInfo.systemUptime
    let inner = runTool("/bin/sleep", ["5"], timeout: 0.1)
    guard inner.status == 124, confirmedAuthorizedToolStatus(inner.status) == 1,
          confirmedAuthorizedToolStatus(125) == 125,
          executeBeforeDeadline("/bin/sh", ["-c", "exit 1"], deadline: ProcessInfo.processInfo.systemUptime + 2).0 == 1 else { return false }
    let timed = executeBeforeDeadline("/bin/sh", ["-c", "sleep 5"], deadline: ProcessInfo.processInfo.systemUptime + 0.1)
    guard timed.0 == 125, ProcessInfo.processInfo.systemUptime - start < 3,
          executeBeforeDeadline("/usr/bin/true", [], deadline: start - 1).0 != 0,
          executeBeforeDeadline("/usr/bin/printf", ["%s", "ok"], deadline: ProcessInfo.processInfo.systemUptime + 2).0 == 0,
          !authorizedSystemArguments(["/bin/sh", "-c", "anything"], device: "disk6s1"),
          !authorizedSystemArguments(["/usr/sbin/diskutil", "unmount", "disk7s1"], device: "disk6s1"),
          !authorizedSystemArguments(["/bin/rmdir", "/Volumes/other"], device: "disk6s1") else { return false }
    print("PASS accepted work is bounded by its absolute deadline, expired work is refused and wrapper timeout retains status 125")
    return true
}
